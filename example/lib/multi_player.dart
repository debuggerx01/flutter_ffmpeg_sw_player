import 'dart:io';
import 'package:flutter_ffmpeg_sw_player/flutter_ffmpeg_sw_player.dart';

import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class MultiPlayerPage extends StatefulWidget {
  const MultiPlayerPage({super.key});

  @override
  State<MultiPlayerPage> createState() => _MultiPlayerPageState();
}

class _MultiPlayerPageState extends State<MultiPlayerPage> {
  final controllers = <String, FfmpegPlayerController>{};

  @override
  void dispose() {
    super.dispose();
    for (var controller in controllers.values) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('拖拽视频或文件夹添加播放窗口'),
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
                        if (!controllers.containsKey(path.path)) {
                          controllers[path.path] = FfmpegPlayerController()..play(path.path);
                        }
                      }
                    } else {
                      if (!controllers.containsKey(path)) {
                        controllers[path] = FfmpegPlayerController()..play(path);
                      }
                    }
                    setState(() {});
                  }
                },
              );
            }
          }
        },
        child: GridView.count(
          crossAxisCount: 6,
          childAspectRatio: 800 / 480,
          crossAxisSpacing: 10,
          mainAxisSpacing: 6,
          children: controllers.values
              .map(
                (e) => FfmpegPlayerView(controller: e),
              )
              .toList(),
        ),
      ),
    );
  }
}
