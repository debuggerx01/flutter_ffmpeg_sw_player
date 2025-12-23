import 'package:flutter/scheduler.dart';

class FpsTicker {
  int _frameCount = 0;
  Ticker? _ticker;

  void start({
    required double fps,
    required void Function(int frameCount) onTick,
  }) {
    stop();
    _ticker = Ticker(
      (elapsed) {
        if (elapsed.inMilliseconds > _frameCount * (1000 / fps)) {
          onTick(_frameCount);
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
