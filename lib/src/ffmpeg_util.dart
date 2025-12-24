import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'media_info.dart';

String? _ffmpegBinaryPath;

class FfmpegUtil {
  static void setBinaryPath(String path) {
    _ffmpegBinaryPath = path;
  }

  static MediaInfo? fetchMediaInfoFromLogs(List<String> logs) {
    String? durationStr = '';
    int? width;
    int? height;
    double? fps;
    for (var line in logs) {
      if (!line.startsWith('  Duration:') && !line.startsWith('  Stream')) continue;
      if (line.startsWith('  Duration:')) {
        var firstMatch = RegExp(r' ([0-9]+:[0-9]+:[0-9]+\.[0-9]+),').firstMatch(line);
        if (firstMatch != null && firstMatch.groupCount > 0) {
          durationStr = firstMatch.group(1);
        }
      } else if (line.contains('Stream') && line.contains('Video:')) {
        var firstMatch = RegExp(r' ([0-9]+x[0-9]+)[, ].+ ([0-9]+\.?[0-9]+?) fps,').firstMatch(line);
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

  static MediaInfo? getMediaInfo(String path) {
    var result = Process.runSync(
      _ffmpegBinaryPath ?? (Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg'),
      ['-i', path],
      runInShell: true,
    );

    return FfmpegUtil.fetchMediaInfoFromLogs(result.stderr.toString().split('\n'));
  }

  static Future<(int, StreamSubscription<List<int>>)> playFile(
    String path, {
    required void Function(List<int> chunk) onData,
    required void Function(String line)? onInfo,
    bool needMediaInfoLogs = true,
  }) {
    return Process.start(
      _ffmpegBinaryPath ?? (Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg'),
      [
        '-i', path,
        '-an',
        // 关键参数：把进度信息以 key=value 格式写到 stderr (pipe:2)
        '-progress', 'pipe:2',
        '-f', 'rawvideo',
        '-pix_fmt', 'bgra',
        // loglevel error 可以减少不必要的日志，但 -progress 的输出依然会被打印
        '-loglevel', needMediaInfoLogs ? 'info' : 'error',
        '-',
      ],
    ).then(
      (p) {
        var streamSubscription = p.stdout.listen(onData);
        p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
          (event) {
            onInfo?.call(event);
          },
        );
        return (p.pid, streamSubscription);
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
