class MediaInfo {
  final Duration duration;
  final int width;
  final int height;
  final double fps;

  MediaInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
  });

  @override
  String toString() => '${width}x$height@$fps fps, Duration: ${duration.toString()}';
}
