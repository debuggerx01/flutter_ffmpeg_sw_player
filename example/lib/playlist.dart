import 'dart:io';
import 'package:flutter_ffmpeg_sw_player/flutter_ffmpeg_sw_player.dart';
import 'package:path/path.dart';

import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class PLayListPage extends StatefulWidget {
  const PLayListPage({super.key});

  @override
  State<PLayListPage> createState() => _PLayListPageState();
}

class _PLayListPageState extends State<PLayListPage> {
  late Set<String> playList = {};
  final FfmpegPlayerController controller = FfmpegPlayerController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('拖拽视频或文件夹添加到播放列表'),
      ),
      body: DropRegion(
        formats: [Formats.fileUri],
        onDropOver: (DropOverEvent p1) => DropOperation.copy,
        onPerformDrop: (PerformDropEvent evt) async {
          for (var item in evt.session.items) {
            if (item.canProvide(Formats.fileUri)) {
              item.dataReader!.getValue(
                Formats.uri,
                (uri) {
                  if (uri != null) {
                    var path = uri.uri.toFilePath();
                    var dir = Directory(path);
                    if (dir.existsSync()) {
                      for (var path in dir.listSync()) {
                        playList.add(path.path);
                      }
                    } else {
                      playList.add(path);
                    }
                    setState(() {});
                  }
                },
              );
            }
          }
        },
        child: Row(
          children: [
            Flexible(
              child: Center(
                child: SizedBox(
                  width: 800,
                  height: 480,
                  child: FfmpegPlayerView(
                    controller: controller,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 500,
              child: ListView.builder(
                itemBuilder: (context, index) {
                  var emoticon = playList.elementAt(index);
                  return ListTile(
                    title: Text(
                      basename(emoticon),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      controller.play(emoticon, loop: true).then(
                        (mediaInfo) {
                          print(mediaInfo);
                        },
                      );
                    },
                  );
                },
                itemCount: playList.length,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
