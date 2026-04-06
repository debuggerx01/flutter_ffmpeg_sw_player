import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'media_info.dart';

String? _ffmpegBinaryPath;

extension LimitedQueue<E> on ListQueue<E> {
  void addLimit(E element, int limit) {
    if (length >= limit) {
      removeFirst();
    }
    addLast(element);
  }
}

class FfmpegUtil {
  static final RegExp _durationRegex = RegExp(r' ([0-9]+:[0-9]+:[0-9]+\.[0-9]+),');
  static final RegExp _videoStreamRegex = RegExp(r' ([0-9]+x[0-9]+)[, ].+? ([0-9]+(?:\.[0-9]+)?)\s+fps');

  static Future<void> setupFromAsset(String assetsKey, [bool forceUpdate = false]) async {
    var directory = await getApplicationSupportDirectory();
    _ffmpegBinaryPath = '${directory.path}/3rd_party/ffmpeg';
    var ffmpegBinaryFile = File(_ffmpegBinaryPath!);
    if (ffmpegBinaryFile.existsSync() && !forceUpdate) {
      return;
    }

    final data = await rootBundle.load(assetsKey);
    if (!ffmpegBinaryFile.existsSync()) {
      await ffmpegBinaryFile.create(recursive: true);
      await ffmpegBinaryFile.writeAsBytes(data.buffer.asUint8List());
      setBinaryPath(ffmpegBinaryFile.path);
    }
  }

  static bool setBinaryPath(String path) {
    var file = File(path);
    if (!file.existsSync()) return false;

    _ffmpegBinaryPath = path;
    var stat = file.statSync();
    if (Platform.isLinux) {
      if (stat.mode & 0x40 == 0) {
        Process.runSync('chmod', ['u+x', _ffmpegBinaryPath!]);
      }
    }
    return true;
  }

  static MediaInfo? fetchMediaInfoFromLogs(List<String> logs) {
    String? durationStr;
    int? width;
    int? height;
    double? fps;

    for (var line in logs) {
      if (line.startsWith('  Duration:')) {
        var firstMatch = _durationRegex.firstMatch(line);
        if (firstMatch != null && firstMatch.groupCount > 0) {
          durationStr = firstMatch.group(1);
        }
      } else if (line.contains('Stream') && line.contains('Video:')) {
        var firstMatch = _videoStreamRegex.firstMatch(line);
        if (firstMatch != null && firstMatch.groupCount > 1) {
          var parts = firstMatch.group(1)!.split('x');
          width = int.tryParse(parts.first);
          height = int.tryParse(parts.last);
          fps = double.tryParse(firstMatch.group(2)!);
        }
      }
    }

    if (durationStr == null || width == null || height == null || fps == null) return null;

    return MediaInfo(
      duration: durationStr.toDuration,
      width: width,
      height: height,
      fps: fps,
    );
  }

  static Future<MediaInfo?> getMediaInfo(String path) async {
    var result = await Process.run(
      _ffmpegBinaryPath ?? (Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg'),
      ['-i', path],
      runInShell: true,
    );

    return FfmpegUtil.fetchMediaInfoFromLogs(result.stderr.toString().split('\n'));
  }

  static Future<(Function, StreamSubscription<List<int>>)> playFile(
    String path, {
    required bool isLive,
    required void Function(List<int> chunk) onData,
    required void Function(String line)? onInfo,
    required void Function(int code, List<String> info)? onError,
    bool needMediaInfoLogs = true,
    List<String> Function(String path, bool needMediaInfoLogs, bool isLive)? commandBuilder,
  }) {
    return Process.start(
      _ffmpegBinaryPath ?? (Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg'),
      commandBuilder?.call(path, needMediaInfoLogs, isLive) ??
          [
            '-i',
            path,
            if (isLive) ...[
              '-fflags',
              'nobuffer',
              '-flags',
              'low_delay',
            ],
            '-preset',
            'ultrafast',
            '-tune',
            'zerolatency',
            '-an',
            '-progress',
            'pipe:2',
            '-f',
            'rawvideo',
            '-pix_fmt',
            'yuv420p',
            '-loglevel',
            needMediaInfoLogs ? 'info' : 'error',
            '-',
          ],
    ).then(
      (p) {
        var killedByStop = false;
        var streamSubscription = p.stdout.listen(onData);
        var lastInfo = ListQueue<String>(30);

        p.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(
          (event) {
            onInfo?.call(event);
            if (onError != null) {
              lastInfo.addLimit(event, 30);
            }
          },
        );

        p.exitCode.then(
          (code) {
            if (!killedByStop && code != 0 && onError != null) {
              onError.call(code, lastInfo.toList(growable: false));
            }
          },
        );

        return (
          () {
            killedByStop = true;
            p.kill();
          },
          streamSubscription,
        );
      },
    );
  }
}

extension DurationExt on String {
  Duration get toDuration {
    var parts = split(':');
    if (parts.length != 3) {
      return Duration.zero;
    }
    return Duration(
      hours: int.parse(parts[0]),
      minutes: int.parse(parts[1]),
      milliseconds: (double.parse(parts[2]) * 1000).round(),
    );
  }
}
