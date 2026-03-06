# flutter_ffmpeg_sw_player

一个基于 FFmpeg 管道输出的 Flutter 视频软渲染插件，专为解决 Linux 平台下视频播放的稳定性与依赖痛点而设计。

## 🚀 为什么选择本插件？

在 Linux 桌面端开发中，传统的播放器方案（如 fvp 或 media_kit）虽然功能强大，但在某些场景下存在以下挑战：

1. 稳定性问题：在 Linux 下使用 fvp 等插件长时间播放视频流时，偶现应用整体界面卡死。
2. 依赖复杂：media_kit 等方案通常深度依赖 libmpv，在部分精简版 Linux 系统中安装依赖较为繁琐。

flutter_ffmpeg_sw_player 通过直接调用 FFmpeg 进程并解析其标准输出（stdout）的原始视频帧进行渲染，避开了复杂的 C/C++ 库深度链接，提供了一个更轻量、更稳定的替代方案。

## ✨ 功能特性

* 低依赖：只需系统环境中有 ffmpeg 执行文件即可工作，无需安装复杂的开发头文件或库。
* 高稳定性：利用独立的子进程解码，即便解码出现异常也不会导致 Flutter 主进程卡死。
* 灵活渲染：
    * 支持 Texture 模式：利用纹理共享提高渲染效率。
    * 支持 RawImage 模式：不依赖 GPU 纹理，纯软绘兼容性更佳。
* 多实例支持：轻松实现视频墙监控等场景。
* 支持直播视频流播放，已测试RTMP、RTSP、HLS和SRT

## ⚠️ 限制说明 (Limitations)

由于其实现机制的特殊性，本插件不适合所有场景：

1. 无音频播放：插件目前仅处理视频流，不提供声音输出。
2. 缺少 Seek 功能：目前仅支持流式顺序播放，不支持跳转进度。
3. 性能开销：采用软件解码和数据拷贝，CPU 占用率会高于硬件解码方案，不建议用于 4K 等超高清视频。

## 📦 安装与配置

### 1. 环境准备

确保您的 Linux 系统中已安装 ffmpeg。

```bash
sudo apt install ffmpeg
```

或者在代码中手动指定 ffmpeg 的二进制路径：

```dart
FfmpegUtil.setBinaryPath('/path/to/your/ffmpeg');
```
> 经测试，ffmpeg v6.1版本在二进制文件尺寸和性能方面表现出色，建议从如下地址下载静态编译的版本：[FFmpeg-Builds -- Auto-Build 2025-08-31](https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2025-08-31-13-00)
> 
> x64: https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2025-08-31-13-00/ffmpeg-n6.1.3-linux64-lgpl-6.1.tar.xz
> 
> arm64: https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2025-08-31-13-00/ffmpeg-n6.1.3-linuxarm64-lgpl-6.1.tar.xz
> 
> 下载后解压获取 `bin/ffmpeg`，可以考虑将其放在项目的assets中，应用启动时通过调用 `FfmpegUtil.setupFromAsset` 方法自动处理。

### 2. 添加依赖

将此插件添加到您的 pubspec.yaml 中。

## 🛠️ 快速开始

### 基础用法

```dart
import 'package:flutter_ffmpeg_sw_player/flutter_ffmpeg_sw_player.dart';

// 1. 创建控制器
final controller = FfmpegPlayerController();

// 2. 开始播放
controller.play(
  'https://example.com/video.mp4',
  onProgress: (pos) => print('当前进度: $pos'),
  onComplete: () => print('播放完成'),
  onError: (code, info) => print('播放异常: $code, $info'),
);


// 3. 在 UI 中显示
@override
Widget build(BuildContext context) {
  return FfmpegPlayerView(
    controller: controller,
    fit: BoxFit.contain,
    useTextureRender: true, // 是否使用纹理加速
  );
}

// 4. 销毁
@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

## 🎮 控制器 API

| 方法/属性                               | 说明                                                                             |
|:------------------------------------|:-------------------------------------------------------------------------------|
| play(path, {loop, onProgress, ...}) | 开始播放视频文件或网络流，可以通过返回值是否为null判断视频解析是否发生异常                                        |
| stop()                              | 停止播放并重置状态                                                                      |
| togglePlay()                        | 切换 暂停/播放 状态                                                                    |
| status                              | ValueNotifier\<PlayerStatus\> 监听播放器状态 (idle, loading, playing, pausing, error) |
| dispose()                           | 释放资源，关闭 FFmpeg 进程                                                              |

> 为防止不再使用播放器时，由于忘记调用控制器的 dispose 方法导致后台 ffmpeg 进程持续解码占用资源，默认情况下 `FfmpegPlayerView` 销毁时会自动调用控制器的 dispose 方法。如果确实需要页面内临时移除 `FfmpegPlayerView` 但不销毁控制器，请使用 `FfmpegPlayerController(autoDispose: true)` 构造或手动将 `autoDispose` 属性设置为 `false`，并确保在页面销毁时调用 `controller.dispose()`。


## 🤝 贡献与反馈

如果您在使用过程中遇到问题，或者有更好的改进建议，欢迎提交 Issue 或 Pull Request。

---

注意：本插件主要针对 Linux 平台开发测试，windows和mac理论上也支持，请自行修改测试。
