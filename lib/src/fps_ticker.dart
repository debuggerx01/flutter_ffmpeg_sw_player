import 'package:flutter/scheduler.dart';

class FpsTicker {
  int _frameCount = 0;
  Ticker? _ticker;

  void start({
    // 如果是 0 则表示不限制帧率，可以用于直播流
    required double fps,
    required void Function(int frameCount, bool skipThisFrame) onTick,
  }) {
    stop();
    _ticker = Ticker(
      (elapsed) {
        if (fps <= 0) {
          onTick(_frameCount, false);
          _frameCount++;
          return;
        }
        while (elapsed.inMilliseconds > _frameCount * (1000 / fps)) {
          onTick(_frameCount, elapsed.inMilliseconds > (_frameCount + 1) * (1000 / fps));
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
    }
    _frameCount = 0;
  }

  void pause() {
    _ticker?.muted = true;
  }

  void resume() {
    _ticker?.muted = false;
  }
}
