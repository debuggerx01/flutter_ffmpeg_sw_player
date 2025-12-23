import 'package:flutter/material.dart';
import 'package:flutter_ffmpeg_sw_player/flutter_ffmpeg_sw_player.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class SinglePlayerPage extends StatefulWidget {
  const SinglePlayerPage({super.key});

  @override
  State<SinglePlayerPage> createState() => _SinglePlayerPageState();
}

class _SinglePlayerPageState extends State<SinglePlayerPage> {
  final FfmpegPlayerController playerController = FfmpegPlayerController();
  MediaInfo? mediaInfo;
  Duration pos = Duration.zero;
  DateTime? startTime;

  @override
  void initState() {
    super.initState();
    playerController
        .play(
          'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
          onProgress: (pos) {
            if (mounted) {
              setState(() {
                this.pos = pos;
              });
            }
          },
        )
        .then(
          (value) {
            if (mounted) {
              setState(() {
                mediaInfo = value;
                startTime = DateTime.now();
              });
            }
          },
        );
  }

  @override
  void dispose() {
    playerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('拖拽视频文件播放'),
      ),
      body: DropRegion(
        formats: [
          Formats.fileUri,
          Formats.mp4,
          Formats.mov,
          Formats.m4v,
          Formats.avi,
          Formats.mpeg,
          Formats.webm,
          Formats.wmv,
          Formats.flv,
          Formats.mkv,
        ],
        onDropOver: (DropOverEvent p1) => DropOperation.copy,
        onPerformDrop: (PerformDropEvent evt) async {
          if (evt.session.items.isNotEmpty) {
            var item = evt.session.items.first;
            if (item.dataReader != null && item.dataReader!.canProvide(Formats.fileUri)) {
              item.dataReader!.getValue(
                Formats.fileUri,
                (uri) {
                  if (uri != null) {
                    playerController
                        .play(
                          uri.toFilePath(),
                          onProgress: (pos) {
                            if (mounted) {
                              setState(() {
                                this.pos = pos;
                              });
                            }
                          },
                        )
                        .then(
                          (value) {
                            if (mounted) {
                              setState(() {
                                mediaInfo = value;
                                startTime = DateTime.now();
                              });
                            }
                          },
                        );
                  }
                },
              );
            }
          }
        },
        child: Center(
          child: Stack(
            alignment: AlignmentGeometry.topLeft,
            fit: StackFit.expand,
            children: [
              FfmpegPlayerView(
                controller: playerController,
                useTextureRender: false,
              ),
              if (mediaInfo != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    '${pos.toString()}(${(pos.inMilliseconds * 100 / mediaInfo!.duration.inMilliseconds).toStringAsFixed(1)}%)'
                    '\n'
                    '${now.difference(startTime ?? now).toString()}',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: ValueListenableBuilder(
        valueListenable: playerController.status,
        builder: (context, status, child) {
          if ([PlayerStatus.playing, PlayerStatus.pausing].contains(status)) {
            var playing = status == PlayerStatus.playing;
            return FloatingActionButton(
              onPressed: () {
                playerController.togglePlay();
              },
              child: Icon(
                playing ? Icons.pause : Icons.play_arrow,
              ),
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }
}
