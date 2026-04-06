import 'package:flutter/scheduler.dart';

class FpsTicker {
  int _frameCount = 0;
  Ticker? _ticker;

  // 用于计算增量时间
  Duration _lastElapsed = Duration.zero;

  // 累加的有效运行时间（微秒），避免暂停/恢复时的时间跳跃
  int _accumulatedMicroseconds = 0;
  bool _isPaused = false;

  void start({
    // 如果是 0 则表示不限制帧率，可以用于直播流
    required double fps,
    required void Function(int frameCount, bool skipThisFrame) onTick,
  }) {
    stop();

    _isPaused = false;
    _lastElapsed = Duration.zero;
    _accumulatedMicroseconds = 0;

    final double frameDurationUs = fps > 0 ? 1000000 / fps : 0;

    _ticker = Ticker(
      (elapsed) {
        final int deltaUs = (elapsed - _lastElapsed).inMicroseconds;
        _lastElapsed = elapsed;

        // 如果处于暂停状态，不累加时间，直接返回
        if (_isPaused) return;

        _accumulatedMicroseconds += deltaUs;

        if (fps <= 0) {
          onTick(_frameCount, false);
          _frameCount++;
          return;
        }

        // 使用累加的微秒时间和预计算的单帧耗时进行判断
        while (_accumulatedMicroseconds >= _frameCount * frameDurationUs) {
          bool skipThisFrame = _accumulatedMicroseconds > (_frameCount + 1) * frameDurationUs;
          onTick(_frameCount, skipThisFrame);
          _frameCount++;
        }
      },
    );
    _ticker!.start();
  }

  void stop() {
    if (_ticker?.isActive == true) {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
    }
    _frameCount = 0;
    _isPaused = false;
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }
}
