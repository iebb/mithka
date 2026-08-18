# Mithka

[English](README.md) | 简体中文

Mithka 是一款独立开发的 Telegram 跨平台客户端，支持 Android、iOS、Windows、
macOS 和 Linux。它以 Flutter 构建界面，通过 Dart FFI 接入
[TDLib](https://core.telegram.org/tdlib)，在手机和桌面设备上提供紧凑且贴近原生体验的
即时通信界面。

> [!IMPORTANT]
> Mithka 是独立开发的非官方项目，与 Telegram 不存在任何隶属、认可或其他关联。
> “Telegram”商标归其权利人所有。
>
> Mithka 同样与腾讯或 QQ 不存在任何隶属、认可、赞助或其他关联。项目不使用、包含、
> 复制或再分发任何 QQ 专有资源。“腾讯”“QQ”及其相关商标和资源均归各自所有者所有。
>
> Mithka 使用你自行提供的 Telegram API 凭据，通过 TDLib 连接 Telegram。请自行承担
> 使用风险，并遵守 Telegram 的[服务条款](https://telegram.org/tos)和
> [API 条款](https://core.telegram.org/api/terms)。

## 可用版本

| 平台 | 测试版 | 稳定版 |
| --- | --- | --- |
| Android | [Google Play 公开测试](https://play.google.com/apps/testing/ad.neko.mithka) | [Google Play](https://play.google.com/store/apps/details?id=ad.neko.mithka) |
| iOS | [TestFlight](https://testflight.apple.com/join/tVC8WkbW) | [App Store](https://apps.apple.com/us/app/mithka/id6783830742) |
| Windows | [GitHub 预发布版](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新 GitHub 正式版](https://github.com/iebb/mithka/releases/latest) |
| macOS | [GitHub 预发布版](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新 GitHub 正式版](https://github.com/iebb/mithka/releases/latest) |
| Linux | [GitHub 预发布版](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新 GitHub 正式版](https://github.com/iebb/mithka/releases/latest) |

## 为什么叫“Mithka”？

这个名称来自企鹅吉祥物与两个微小质量单位之间的文字游戏：

- 企鹅吉祥物引出了 **pengram**：🐧 + *gram*。将其读作 *penta-gram*，约等于
  **5 克**。
- 一 **mithqāl**（مثقال）是伊斯兰传统质量单位，约等于 **4.6875 克**。

**Mithka** 一词源自 *mithqāl*；在想象中的天平上，它恰好比（Tele）gram 企鹅更轻
一点。

## 主要功能

Mithka 通过 TDLib 连接你真实的 Telegram 账号和聊天。自定义界面包含实时更新的聊天
列表与会话、表情回应、贴纸（包括 `.tgs` 和 `.webm` 动画格式）、语音消息、投票、
清单、Telegram 社群（Communities）、位置共享、联系人、个人资料、类似朋友圈的动态、
设置，以及一对一通话界面。

## 技术架构

- Flutter 界面位于 `lib/`，使用 `provider` 和 `ChangeNotifier` 管理状态。
- TDLib 通过 `lib/tdlib/` 中的 Dart FFI 接入。各平台使用固定版本的原生
  `libtdjson` 二进制文件，该文件不会提交到本仓库。
- 界面可自适应浅色与深色主题，并使用 Cupertino 和自定义组件，不使用 Material
  对话框、提示条（Snackbar）或开关。

## 从源码构建

### 1. 添加 Telegram API 凭据

在 <https://my.telegram.org> 创建你自己的 `api_id` 和 `api_hash`，然后将它们写入已在
`.gitignore` 中排除的 `lib/config/secrets.dart`：

```dart
class Secrets {
  static const int apiId = 123456;
  static const String apiHash = 'your_api_hash';
  static bool get isConfigured => apiId != 0 && apiHash.isNotEmpty;
}
```

### 2. 安装原生 TDLib 库

[`scripts/tdjson-manifest.json`](scripts/tdjson-manifest.json) 固定了
[`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson) 所发布的 Android、iOS、
macOS、Linux 和 Windows 预编译产物版本。辅助脚本会下载并校验这些产物；本仓库不再
从源码编译 TDLib。

```bash
# Android：在 android/app/src/main/jniLibs/<abi>/ 下安装一个或多个 ABI
scripts/build-tdjson-android.sh arm64-v8a

# iOS：为 Runner target 安装 ios/tdjson/tdjson.xcframework
scripts/build-tdjson-ios.sh

# 桌面平台：将库写入指定路径（linux、macos 或 windows）
scripts/build-tdjson-desktop.sh macos /tmp/libtdjson.dylib
```

下载的库是可复现的本地构建输入。你可以保留当前构建平台所需的库；如果需要释放磁盘
空间，也可以删除它，并在下次构建前重新运行对应脚本。旧版 `.tdlib-build/` 源码构建
目录（包括体积较大的 `libtdcore.a` 归档）不是运行时依赖，可以安全删除。准确路径和
清理建议请参阅 [NATIVE.md](NATIVE.md)。

### 3. 获取依赖并运行

```bash
flutter pub get
flutter run # 在已连接的设备或模拟器上运行
```

本地开发不强制使用 Firebase Analytics。如果缺少
`android/app/google-services.json` 或 `ios/Runner/GoogleService-Info.plist`，或者文件
只是空占位内容，应用仍可正常构建和运行，但分析功能会被禁用。维护者和发布 CI 会自动
提供真实且已被 Git 忽略的配置文件。

### Android 发布签名

当 `android/key.properties` 及其引用的密钥库存在时，Android 发布构建会使用项目的
上传密钥签名；否则使用调试签名。这两个文件都不会提交到仓库。

## CI 与发布流程

- `master` 是通过验证的开发分支，不会向 GitHub、Google Play 或 TestFlight 发布
  安装包。
- 将经过验证的 `master` 提交推送到 `release-ios` 后，Xcode Cloud 会为 iOS 和 macOS
  创建归档，并将构建交付给 TestFlight 外部测试人员。Xcode Cloud 保持主版本号和次
  版本号不变，同时将修订版本号设为 `0`。
- 每天 00:00 UTC，GitHub Actions 会将 `master` 的新提交合并到 `nightly`，并将应用
  修订版本号递增一次。该工作流会发布带日期的 Android、Windows、macOS 和 Linux
  GitHub 预发布版，并将已签名的 Android App Bundle 提交到 Google Play 公开测试。
- 推送到 `release` 会发布带日期的多平台 GitHub 稳定版，并通过同一个可识别发布渠道的
  工作流，将生产用 Android App Bundle 提交到 Google Play。

在 CI 运行器上，`secrets.dart` 会根据仓库机密变量 `TELEGRAM_API_ID` 和
`TELEGRAM_API_HASH` 自动生成。

## 许可证与致谢

Mithka 采用 [BSD 3-Clause License](LICENSE) 开源。

TDLib 以及 `third_party/` 中的组件分别遵循各自的许可证。Mithka 不随应用分发任何
第三方应用的专有资源或商标。

## Star 趋势

<a href="https://www.star-history.com/?repos=iebb%2Fmithka&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&theme=dark&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <img alt="Star History 趋势图" src="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
 </picture>
</a>
