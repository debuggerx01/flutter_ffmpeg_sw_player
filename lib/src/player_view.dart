import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_ffmpeg_sw_player/src/controller.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';

class FfmpegPlayerView extends StatefulWidget {
  final FfmpegPlayerController controller;
  final bool useTextureRender;
  final BoxFit fit;

  const FfmpegPlayerView({
    super.key,
    this.useTextureRender = true,
    this.fit = BoxFit.contain,
    required this.controller,
  });

  @override
  State<FfmpegPlayerView> createState() => _FfmpegPlayerViewState();
}

class _FfmpegPlayerViewState extends State<FfmpegPlayerView> {
  late final TextureRgbaRenderer _textureRgbaRendererPlugin;
  late final int _key;
  int? _textureId;
  int? _texturePtr;
  ui.Image? frameImage;
  ui.Size size = ui.Size.zero;

  @override
  void initState() {
    super.initState();
    if (widget.useTextureRender) {
      _textureRgbaRendererPlugin = TextureRgbaRenderer();

      _key = DateTime.now().microsecondsSinceEpoch;
      _textureRgbaRendererPlugin.createTexture(_key).then((textureId) {
        if (textureId != -1) {
          _textureRgbaRendererPlugin.getTexturePtr(_key).then(
            (ptr) {
              if (mounted) {
                setState(() {
                  _texturePtr = ptr;
                });
              }
            },
          );
          if (mounted) {
            setState(() {
              _textureId = textureId;
            });
          }
          widget.controller.setOnFrame(
            (
              dataPtr,
              width,
              height,
            ) {
              if (size.width != width.toDouble() || size.height != height.toDouble()) {
                if (mounted) {
                  setState(() {
                    size = ui.Size(width.toDouble(), height.toDouble());
                  });
                }
              }
              Native.instance.onRgba(
                Pointer.fromAddress(_texturePtr!).cast<Void>(),
                dataPtr,
                width * height * 4,
                width,
                height,
                1,
              );
            },
          );
        }
      });
    } else {
      widget.controller.setOnFrame(
        (frameDataPtr, width, height) {
          ui.decodeImageFromPixels(
            frameDataPtr.asTypedList(width * height * 4),
            width,
            height,
            ui.PixelFormat.bgra8888,
            (result) {
              if (mounted) {
                setState(() {
                  frameImage = result;
                });
              }
            },
          );
        },
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
    if (widget.useTextureRender) {
      _textureRgbaRendererPlugin.closeTexture(_key);
    }
    widget.controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.useTextureRender) {
      return RawImage(
        fit: widget.fit,
        image: frameImage,
      );
    }
    return _textureId == null
        ? const SizedBox.shrink()
        : FittedBox(
            fit: widget.fit,
            child: SizedBox.fromSize(
              size: size,
              child: Texture(
                textureId: _textureId!,
                filterQuality: FilterQuality.none,
              ),
            ),
          );
  }
}
