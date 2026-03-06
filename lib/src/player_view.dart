import 'dart:async';
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

  Timer? blackScreenTimer;
  bool _showBlackScreen = false;

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

    widget.controller.status.addListener(_handlePlayStatus);
  }

  void _handlePlayStatus() {
    if (blackScreenTimer?.isActive == true) {
      blackScreenTimer?.cancel();
    }
    if ([PlayerStatus.idle, PlayerStatus.error].contains(widget.controller.status.value)) {
      blackScreenTimer = Timer(const Duration(milliseconds: 100), () {
        __showBackScreen(true);
      });
    } else {
      __showBackScreen(false);
    }
  }

  void __showBackScreen(bool show) {
    if (_showBlackScreen != show && mounted) {
      setState(() {
        _showBlackScreen = show;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
    if (widget.useTextureRender) {
      _textureRgbaRendererPlugin.closeTexture(_key);
    }
    if (widget.controller.autoDispose) {
      widget.controller.dispose();
    }
    widget.controller.status.removeListener(_handlePlayStatus);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller.status,
      builder: (context, status, child) {
        return Visibility.maintain(
          visible: !_showBlackScreen,
          child: widget.useTextureRender
              ? (_textureId == null
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
                    ))
              : RawImage(
                  fit: widget.fit,
                  image: frameImage,
                ),
        );
      },
    );
  }
}
