import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ffmpeg_sw_player/src/ffmpeg_util.dart';
import 'package:flutter_ffmpeg_sw_player/src/fps_ticker.dart';
import 'package:flutter_ffmpeg_sw_player/src/media_info.dart';

const cacheFrames = 5;

enum PlayerStatus {
  idle,
  loading,
  playing,
  paused,
  error,
}

const liveSchemas = ['rtmp', 'rtmps', 'rtsp', 'rtsps', 'srt'];

class FfmpegPlayerController {
  /// 当所属的[FfmpegPlayerView]销毁时自动释放持有的资源
  bool autoDispose;

  FfmpegPlayerController({this.autoDispose = true});

  final ValueNotifier<PlayerStatus> status = ValueNotifier(PlayerStatus.idle);
  final FpsTicker _fpsTicker = FpsTicker();
  MediaInfo? _mediaInfo;
  void Function(Pointer<Uint8> frameDataPtr, int width, int height)? _onFrame;

  Pointer<Uint8>? _nativeBuffer;
  // 收纳一帧 YUV 数据的临时 Dart Buffer
  Uint8List? _yuvDartBuffer;

  /// 数据包缓冲区
  final Queue<Uint8List> _chunkQueue = Queue();

  /// 当前数据包缓冲区的总数据长度
  int _totalBufferedBytes = 0;

  /// 当前第一个 chunk 用到了哪里
  int _chunkOffset = 0;

  Function? _currentFfmpegProcessKiller;

  // 渲染时使用的 BGRA 大小
  int get _bgraFrameSize => (_mediaInfo?.width ?? 0) * (_mediaInfo?.height ?? 0) * 4;

  // 管道传入的 YUV420P 大小
  int get _yuvFrameSize => ((_mediaInfo?.width ?? 0) * (_mediaInfo?.height ?? 0) * 3) ~/ 2;

  StreamSubscription<List<int>>? _dataReceiver;

  bool _reachEnd = false;

  int? _currentPlayKey;

  Future<MediaInfo?> play(
    String path, {
    void Function(Duration pos)? onProgress,
    void Function()? onComplete,
    void Function(int code, List<String> info)? onError,
    bool loop = true,
    bool? isLive,
    List<String> Function(String path, bool needMediaInfoLogs, bool isLive)? commandBuilder,
  }) {
    _currentPlayKey = DateTime.now().microsecondsSinceEpoch;
    return _play(
      _currentPlayKey!,
      path,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
      loop: loop,
      isLive: isLive,
      fromLoop: false,
      commandBuilder: commandBuilder,
    );
  }

  Future<MediaInfo?> _play(
    int playKey,
    String path, {
    void Function(Duration pos)? onProgress,
    void Function()? onComplete,
    void Function(int code, List<String> info)? onError,
    required bool fromLoop,
    required bool loop,
    bool? isLive,
    List<String> Function(String path, bool needMediaInfoLogs, bool isLive)? commandBuilder,
  }) {
    Completer<MediaInfo?> completer = Completer();
    var logs = <String>[];
    if (fromLoop) {
      completer.complete(_mediaInfo);
      _currentFfmpegProcessKiller?.call();
      _dataReceiver?.cancel();
      _chunkQueue.clear();
      _chunkOffset = 0;
      _totalBufferedBytes = 0;
    } else {
      stop();
    }
    status.value = PlayerStatus.loading;
    _reachEnd = false;
    isLive ??= liveSchemas.contains(Uri.tryParse(path)?.scheme);
    FfmpegUtil.playFile(
      path,
      needMediaInfoLogs: !fromLoop,
      isLive: isLive,
      commandBuilder: commandBuilder,
      onError: (code, info) {
        status.value = PlayerStatus.error;
        onError?.call(code, info);
      },
      onData: (chunk) {
        if (playKey != _currentPlayKey) return;
        _chunkQueue.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
        _totalBufferedBytes += chunk.length;
        if (_yuvFrameSize != 0 && _dataReceiver != null && _totalBufferedBytes > _yuvFrameSize * cacheFrames) {
          /// 如果缓冲区的已有超过[cacheFrames]帧 YUV 数据，就可以先暂停接收了
          _dataReceiver?.pause();
        }
      },
      onInfo: (line) {
        if (playKey != _currentPlayKey) return;
        if (_mediaInfo == null) {
          logs.add(line);
          if (line.startsWith('Output #0, rawvideo,')) {
            _mediaInfo = FfmpegUtil.fetchMediaInfoFromLogs(logs);
            if (_mediaInfo == null) {
              stop(true);
            } else {
              _nativeBuffer = malloc.allocate(_bgraFrameSize);
              _yuvDartBuffer = Uint8List(_yuvFrameSize);
            }
            if (!completer.isCompleted) {
              completer.complete(_mediaInfo);
            }
          } else if (line.startsWith('Error opening input')) {
            stop(true);
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        }
        if (onProgress != null && line.startsWith('out_time=') && !line.endsWith('N/A')) {
          onProgress.call(
            line.split('=').last.toDuration,
          );
        }
        if (line == 'progress=end') {
          _reachEnd = true;
        }
      },
    ).then(
      (res) {
        if (playKey != _currentPlayKey) {
          return;
        }
        _currentFfmpegProcessKiller = res.$1;
        _dataReceiver = res.$2;
      },
    );

    return completer.future.then((mediaInfo) {
      if (playKey == _currentPlayKey && mediaInfo != null) {
        _startRender(
          playKey,
          path,
          loop,
          isLive!,
          onProgress,
          onComplete,
          onError,
          commandBuilder,
        );
      }
      return mediaInfo;
    });
  }

  void _startRender(
    int playKey,
    String path,
    bool loop,
    bool isLive,
    void Function(Duration pos)? onProgress,
    void Function()? onComplete,
    void Function(int code, List<String> info)? onError,
    List<String> Function(String path, bool needMediaInfoLogs, bool isLive)? commandBuilder,
  ) {
    _fpsTicker.start(
      fps: isLive ? 0 : _mediaInfo!.fps,
      onTick: (frameCount, skipThisFrame) {
        if (playKey != _currentPlayKey) return;
        if (_nativeBuffer == null || _yuvDartBuffer == null) return;

        // 如果数据不够一帧 YUV，直接跳过，等待下一次 tick
        if (_totalBufferedBytes < _yuvFrameSize) {
          // 如果之前暂停了，现在数据不够了，赶紧恢复
          if (_dataReceiver?.isPaused == true) {
            _dataReceiver?.resume();
          }
          if (_reachEnd) {
            onComplete?.call();
            _fpsTicker.stop();
            status.value = PlayerStatus.idle;
            if (loop) {
              _play(
                playKey,
                path,
                onProgress: onProgress,
                onComplete: onComplete,
                onError: onError,
                loop: loop,
                fromLoop: true,
                commandBuilder: commandBuilder,
              );
            }
          }
          return;
        }

        if (status.value != PlayerStatus.playing) {
          status.value = PlayerStatus.playing;
        }

        // --- 开始拼凑一帧 YUV 数据 ---
        int bytesFilled = 0;

        while (bytesFilled < _yuvFrameSize) {
          if (_chunkQueue.isEmpty) break; // 防御性检查

          final currentChunk = _chunkQueue.first;

          // 当前 chunk 剩余可用长度
          int availableInChunk = currentChunk.length - _chunkOffset;
          // 还需要填充多少
          int needed = _yuvFrameSize - bytesFilled;

          // 决定拷贝多少
          int toCopy = availableInChunk < needed ? availableInChunk : needed;

          // 使用暂存区承载 YUV
          _yuvDartBuffer!.setRange(bytesFilled, bytesFilled + toCopy, currentChunk, _chunkOffset);

          bytesFilled += toCopy;
          _chunkOffset += toCopy;

          // 如果当前 chunk 用完了，移除它
          if (_chunkOffset >= currentChunk.length) {
            _chunkQueue.removeFirst(); // 移除第一个
            _chunkOffset = 0; // 重置偏移量
          }
        }

        // 更新总缓冲计数 (减去 YUV 的大小)
        _totalBufferedBytes -= _yuvFrameSize;

        // --- 渲染 ---
        if (!skipThisFrame) {
          // 利用高效 Dart 查找表进行软转并写入 Native 的 RGBA buffer
          _convertYuv420pToBgra(_yuvDartBuffer!, _nativeBuffer!, _mediaInfo!.width, _mediaInfo!.height);
          _onFrame?.call(_nativeBuffer!, _mediaInfo!.width, _mediaInfo!.height);
        }

        // 【背压恢复】如果水位降到了 1 帧以内，恢复接收
        if (_dataReceiver?.isPaused == true && _totalBufferedBytes < _yuvFrameSize * cacheFrames) {
          _dataReceiver?.resume();
        }
      },
    );
  }

  /// 高性能 Native 内存零拷贝视角的转换方法
  static void _convertYuv420pToBgra(Uint8List yuv, Pointer<Uint8> bgraPtr, int width, int height) {
    final int size = width * height;
    // 直接映射为 4字节(32位)整型数组，大幅降低写入次数
    final Uint32List bgra = bgraPtr.cast<Uint32>().asTypedList(size);

    int outIdx = 0;
    int yIdx = 0;
    final int uOffset = size;
    final int vOffset = size + (size >> 2); // size + size/4

    for (int j = 0; j < height; j++) {
      int uvpJ = j >> 1;
      int uvIdx = uvpJ * (width >> 1);

      for (int i = 0; i < width; i++) {
        int uvpI = i >> 1;
        int y = yuv[yIdx++];
        int u = yuv[uOffset + uvIdx + uvpI] - 128;
        int v = yuv[vOffset + uvIdx + uvpI] - 128;

        // 经典 YUV to RGB 整数转换算法
        int y1192 = 1192 * (y - 16);
        if (y1192 < 0) y1192 = 0;

        int r = y1192 + 1634 * v;
        int g = y1192 - 833 * v - 400 * u;
        int b = y1192 + 2066 * u;

        r = r < 0 ? 0 : (r > 262143 ? 262143 : r);
        g = g < 0 ? 0 : (g > 262143 ? 262143 : g);
        b = b < 0 ? 0 : (b > 262143 ? 262143 : b);

        // 小端序平台中 Uint32 [Byte0, Byte1, Byte2, Byte3] 的内存布局恰好等于低位到高位
        // BGRA 要求在内存中顺序为: B(byte0), G(byte1), R(byte2), A_255(byte3)
        bgra[outIdx++] = 0xFF000000 | ((r >> 10) << 16) | ((g >> 10) << 8) | (b >> 10);
      }
    }
  }

  void stop([bool error = false]) {
    status.value = error ? PlayerStatus.error : PlayerStatus.idle;
    dispose();
    _mediaInfo = null;
    _chunkQueue.clear();
    _chunkOffset = 0;
    _totalBufferedBytes = 0;
  }

  void dispose() {
    _currentFfmpegProcessKiller?.call();
    _currentFfmpegProcessKiller = null;

    if (_nativeBuffer != null) {
      malloc.free(_nativeBuffer!);
      _nativeBuffer = null;
    }

    _yuvDartBuffer = null;

    _dataReceiver?.cancel();
    _fpsTicker.stop();
  }

  void setOnFrame(void Function(Pointer<Uint8> frameDataPtr, int width, int height)? onFrame) {
    _onFrame = onFrame;
  }

  void togglePlay() {
    if (status.value == PlayerStatus.playing) {
      _fpsTicker.pause();
      status.value = PlayerStatus.paused;
    } else if (status.value == PlayerStatus.paused) {
      _fpsTicker.resume();
      status.value = PlayerStatus.playing;
    }
  }
}
