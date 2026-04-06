import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_ffmpeg_sw_player/flutter_ffmpeg_sw_player.dart';

class ProcessStat {
  final double cpuPercent;
  final double memoryMb;

  ProcessStat({required this.cpuPercent, required this.memoryMb});
}

class PerformanceTester extends StatefulWidget {
  final String testMediaUrl;

  /// 传入需要测试的本地视频路径或直播流URL
  const PerformanceTester({super.key, required this.testMediaUrl});

  @override
  State<PerformanceTester> createState() => _PerformanceTesterState();
}

class _PerformanceTesterState extends State<PerformanceTester> {
  late FfmpegPlayerController _controller;
  Timer? _testTimer;
  int _elapsedSeconds = 0;
  bool _isTesting = false;
  String _report = "点击下方按钮开始1分钟的性能测试 ";

  final List<ProcessStat> _mainProcessStats = [];
  final List<ProcessStat> _ffmpegProcessStats = [];

  @override
  void initState() {
    super.initState();
    _controller = FfmpegPlayerController(autoDispose: true);
  }

  @override
  void dispose() {
    _testTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTest() {
    setState(() {
      _isTesting = true;
      _elapsedSeconds = 0;
      _report = "测试进行中... $_elapsedSeconds / 60 秒";
      _mainProcessStats.clear();
      _ffmpegProcessStats.clear();
    });

    _controller.play(widget.testMediaUrl);

    _testTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _elapsedSeconds++;

      // 收集数据
      final mainStat = await _getProcessStat(pid.toString());
      final ffmpegStat = await _getProcessStat('ffmpeg', isName: true);

      if (mainStat != null) _mainProcessStats.add(mainStat);
      if (ffmpegStat != null) _ffmpegProcessStats.add(ffmpegStat);

      if (mounted) {
        setState(() {
          _report = "测试进行中... $_elapsedSeconds / 60 秒\n"
              "当前主进程: ${mainStat?.cpuPercent ?? 0}% CPU | ${mainStat?.memoryMb.toStringAsFixed(1) ?? 0} MB\n"
              "当前 FFMPEG: ${ffmpegStat?.cpuPercent ?? 0}% CPU | ${ffmpegStat?.memoryMb.toStringAsFixed(1) ?? 0} MB";
        });
      }

      // 到达 60 秒自动停止
      if (_elapsedSeconds >= 60) {
        _stopTestAndGenerateReport();
      }
    });
  }

  void _stopTestAndGenerateReport() {
    _testTimer?.cancel();
    _controller.stop();

    final mainReport = _calculateStats("主程序 (Dart/Flutter)", _mainProcessStats);
    final ffmpegReport = _calculateStats("FFMPEG 子进程", _ffmpegProcessStats);

    setState(() {
      _isTesting = false;
      _report = "=== 1分钟性能测试报告 ===\n\n$mainReport\n$ffmpegReport";
    });

    // 也可以将报告打印到控制台
    debugPrint("\n$_report\n");
  }

  String _calculateStats(String targetName, List<ProcessStat> stats) {
    if (stats.isEmpty) return "[$targetName] 未能采集到有效数据。";

    double maxCpu = 0, minCpu = double.infinity, sumCpu = 0;
    double maxMem = 0, minMem = double.infinity, sumMem = 0;

    for (var stat in stats) {
      maxCpu = max(maxCpu, stat.cpuPercent);
      minCpu = min(minCpu, stat.cpuPercent);
      sumCpu += stat.cpuPercent;

      maxMem = max(maxMem, stat.memoryMb);
      minMem = min(minMem, stat.memoryMb);
      sumMem += stat.memoryMb;
    }

    double avgCpu = sumCpu / stats.length;
    double avgMem = sumMem / stats.length;

    return "[$targetName - 共采集 ${stats.length} 次]\n"
        "  CPU占用: 平均 ${avgCpu.toStringAsFixed(2)}% | 峰值 ${maxCpu.toStringAsFixed(2)}% | 最低 ${minCpu.toStringAsFixed(2)}%\n"
        "  内存占用: 平均 ${avgMem.toStringAsFixed(2)} MB | 峰值 ${maxMem.toStringAsFixed(2)} MB | 最低 ${minMem.toStringAsFixed(2)} MB\n";
  }

  /// 使用 ps 命令通过 PID 或 进程名称 获取 CPU 和 Memory (RSS MB)
  Future<ProcessStat?> _getProcessStat(String query, {bool isName = false}) async {
    try {
      String targetPid = query;
      if (isName) {
        // 先通过 pgrep 获取进程名对应的全部 PID（可能有多个，取第一个）
        final pgrepRes = await Process.run('pgrep', [query]);
        final pids = pgrepRes.stdout.toString().trim().split('\n');
        if (pids.isEmpty || pids.first.isEmpty) return null;
        targetPid = pids.first;
      }

      // 运行: ps -p <PID> -o %cpu,rss
      // rss 单位通常是 KB
      final psRes = await Process.run('ps', ['-p', targetPid, '-o', '%cpu,rss']);
      final lines = psRes.stdout.toString().trim().split('\n');

      if (lines.length > 1) {
        // [1] 取的是数据行，用空白符分割
        final parts = lines[1].trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          double cpu = double.tryParse(parts[0]) ?? 0.0;
          double rssKb = double.tryParse(parts[1]) ?? 0.0;
          double memMb = rssKb / 1024.0;

          return ProcessStat(cpuPercent: cpu, memoryMb: memMb);
        }
      }
    } catch (e) {
      debugPrint("获取进程状态出现错误: $e");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("软解播放器 性能测试工具")),
      body: Column(
        children: [
          // 播放器视图画面
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: FfmpegPlayerView(controller: _controller),
            ),
          ),

          // 报告展示和控制视图
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _isTesting ? null : _startTest,
                    child: Text(_isTesting ? "测试中..." : "开始1分钟性能测试"),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _report,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
