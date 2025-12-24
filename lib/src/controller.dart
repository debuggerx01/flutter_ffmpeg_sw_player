import 'dart:async';
import 'dart:ffi';
import 'dart:io';

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
  pausing,
  error,
}

class FfmpegPlayerController {
  final ValueNotifier<PlayerStatus> status = ValueNotifier(PlayerStatus.idle);
  final FpsTicker _fpsTicker = FpsTicker();
  MediaInfo? _mediaInfo;
  void Function(Pointer<Uint8> frameDataPtr, int width, int height)? _onFrame;

  Pointer<Uint8>? _nativeBuffer;

  /// 数据包缓冲区
  final List<List<int>> _chunkQueue = [];

  /// 当前数据包缓冲区的总数据长度
  int _totalBufferedBytes = 0;

  /// 当前第一个 chunk 用到了哪里
  int _chunkOffset = 0;

  int? _currentFfmpegPid;

  int get _currentBufferSize => (_mediaInfo?.width ?? 0) * (_mediaInfo?.height ?? 0) * 4;

  StreamSubscription<List<int>>? _dataReceiver;

  bool _reachEnd = false;

  int? _currentPlayKey;

  Future<MediaInfo?> play(
    String path, {
    void Function(Duration pos)? onProgress,
    void Function()? onComplete,
    bool loop = true,
  }) {
    _currentPlayKey = DateTime.now().microsecondsSinceEpoch;
    return _play(
      _currentPlayKey!,
      path,
      onProgress: onProgress,
      onComplete: onComplete,
      loop: loop,
      fromLoop: false,
    );
  }

  Future<MediaInfo?> _play(
    int playKey,
    String path, {
    void Function(Duration pos)? onProgress,
    void Function()? onComplete,
    required bool fromLoop,
    required bool loop,
  }) {
    status.value = PlayerStatus.loading;
    Completer<MediaInfo?> completer = Completer();
    var logs = <String>[];
    if (fromLoop) {
      completer.complete(_mediaInfo);
    } else {
      stop();
    }
    _reachEnd = false;
    FfmpegUtil.playFile(
      path,
      needMediaInfoLogs: !fromLoop,
      onData: (chunk) {
        if (playKey != _currentPlayKey) return;
        _chunkQueue.add(chunk);
        _totalBufferedBytes += chunk.length;
        if (_currentBufferSize != 0 && _dataReceiver != null && _totalBufferedBytes > _currentBufferSize * cacheFrames) {
          /// 如果缓冲区的已有超过[cacheFrames]帧数据，就可以先暂停接收了
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
              status.value = PlayerStatus.error;
              stop();
            } else {
              _nativeBuffer = malloc.allocate(_currentBufferSize);
            }
            if (!completer.isCompleted) {
              completer.complete(_mediaInfo);
            }
          } else if (line.startsWith('Error opening input')) {
            status.value = PlayerStatus.error;
            stop();
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
          Process.killPid(res.$1);
          return;
        }
        _currentFfmpegPid = res.$1;
        _dataReceiver = res.$2;
      },
    );

    return completer.future.then((mediaInfo) {
      if (playKey == _currentPlayKey && mediaInfo != null) {
        _startRender(
          playKey,
          path,
          loop,
          onProgress,
          onComplete,
        );
      }
      return mediaInfo;
    });
  }

  void _startRender(
    int playKey,
    String path,
    bool loop,
    void Function(Duration pos)? onProgress,
    void Function()? onComplete,
  ) {
    _fpsTicker.start(
      fps: _mediaInfo!.fps,
      onTick: (frameCount) {
        if (playKey != _currentPlayKey) return;
        if (_nativeBuffer == null) return;

        // print('[$frameCount]\t$currentTime\t${_totalBufferedBytes < _currentBufferSize}\t${_nativeBuffer == null}');
        // 如果数据不够一帧，直接跳过，等待下一次 tick
        if (_totalBufferedBytes < _currentBufferSize) {
          // 如果之前暂停了，现在数据不够了，赶紧恢复
          if (_dataReceiver?.isPaused == true) {
            _dataReceiver?.resume();
          }
          return;
        }

        if (status.value != PlayerStatus.playing) {
          status.value = PlayerStatus.playing;
        }

        // --- 开始拼凑一帧数据 ---
        int bytesFilled = 0;

        while (bytesFilled < _currentBufferSize) {
          if (_chunkQueue.isEmpty) break; // 防御性检查

          final currentChunk = _chunkQueue.first;

          // 当前 chunk 剩余可用长度
          int availableInChunk = currentChunk.length - _chunkOffset;
          // 还需要填充多少
          int needed = _currentBufferSize - bytesFilled;

          // 决定拷贝多少
          int toCopy = availableInChunk < needed ? availableInChunk : needed;

          // 拷贝数据到 Native 内存
          _nativeBuffer!.asTypedList(_currentBufferSize).setRange(bytesFilled, bytesFilled + toCopy, currentChunk, _chunkOffset);

          bytesFilled += toCopy;
          _chunkOffset += toCopy;

          // 如果当前 chunk 用完了，移除它
          if (_chunkOffset >= currentChunk.length) {
            _chunkQueue.removeAt(0); // 移除第一个
            _chunkOffset = 0; // 重置偏移量
          }
        }

        // 更新总缓冲计数
        _totalBufferedBytes -= _currentBufferSize;

        // --- 渲染 ---
        _onFrame?.call(_nativeBuffer!, _mediaInfo!.width, _mediaInfo!.height);

        // 【背压恢复】如果水位降到了 1 帧以内，恢复接收
        if (_dataReceiver?.isPaused == true && _totalBufferedBytes < _currentBufferSize * cacheFrames) {
          _dataReceiver?.resume();
        }

        if (_reachEnd && _totalBufferedBytes == 0) {
          onComplete?.call();
          _fpsTicker.stop();
          status.value = PlayerStatus.idle;
          if (loop) {
            _play(
              playKey,
              path,
              onProgress: onProgress,
              onComplete: onComplete,
              loop: loop,
              fromLoop: true,
            );
          }
        }
      },
    );
  }

  void stop() {
    dispose();
    _mediaInfo = null;
    _chunkQueue.clear();
    _chunkOffset = 0;
    _totalBufferedBytes = 0;
  }

  void dispose() {
    if (_currentFfmpegPid != null) {
      Process.killPid(_currentFfmpegPid!);
    }

    if (_nativeBuffer != null) {
      malloc.free(_nativeBuffer!);
      _nativeBuffer = null;
    }

    _dataReceiver?.cancel();
    _fpsTicker.stop();
  }

  void setOnFrame(void Function(Pointer<Uint8> frameDataPtr, int width, int height)? onFrame) {
    _onFrame = onFrame;
  }

  void togglePlay() {
    if (status.value == PlayerStatus.playing) {
      _fpsTicker.pause();
      status.value = PlayerStatus.pausing;
    } else if (status.value == PlayerStatus.pausing) {
      _fpsTicker.resume();
      status.value = PlayerStatus.playing;
    }
  }
}
