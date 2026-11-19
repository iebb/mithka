# Mithka

![Mithka — 独立开发的 Telegram 客户端](docs/images/mithka-github-banner.png)

[English](README.md) | 简体中文

**Mithka** 是一款轻量、紧凑的跨平台 Telegram 客户端，使用 Flutter 构建界面并通过
Dart FFI 接入 [TDLib](https://core.telegram.org/tdlib)。支持 Android、iOS、macOS、
Windows、Linux 与 HarmonyOS Next，兼顾手机单手操作与平板、桌面端多栏工作区布局。

![Mithka 桌面、iPad 和 iPhone Duo 布局示意图](docs/images/mithka-github-devices.png)

*以上为基于 Mithka 实际界面结构制作的示意图，会话内容均为虚构，并非真机截图。*

> [!IMPORTANT]
> Mithka 是独立开发的非官方项目，与 Telegram 不存在任何隶属、认可或其他关联。
> “Telegram”商标归其权利人所有。
>
> Mithka 同样与腾讯或 QQ 不存在任何隶属、认可、赞助或其他关联。项目不使用、包含、
> 复制或再分发任何 QQ 专有资源。“腾讯”“QQ”及其相关商标和资源均归各自所有者所有。
>
> 从源码构建时，Mithka 使用你自行提供的 Telegram API 凭据通过 TDLib 连接
> Telegram。请遵守 Telegram 的[服务条款](https://telegram.org/tos)与
> [API 条款](https://core.telegram.org/api/terms)。

---

## 下载与支持平台

| 平台 | 测试版 / 每夜构建 | 正式版 |
| --- | --- | --- |
| **Android** | [Google Play 公开测试](https://play.google.com/apps/testing/ad.neko.mithka) · [GitHub APK](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Google Play](https://play.google.com/store/apps/details?id=ad.neko.mithka) · [GitHub 正式版](https://github.com/iebb/mithka/releases/latest) |
| **iOS & iPadOS** | [TestFlight](https://testflight.apple.com/join/tVC8WkbW) | [App Store](https://apps.apple.com/us/app/mithka/id6783830742) |
| **macOS 12+** (`arm64`, `x64`) | [TestFlight](https://testflight.apple.com/join/tVC8WkbW) · [GitHub 预发布版](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Mac App Store](https://apps.apple.com/us/app/mithka/id6783830742?platform=mac) · [GitHub 正式版](https://github.com/iebb/mithka/releases/latest) |
| **Windows** (`x64`, `arm64`) | [GitHub 预发布版](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新 GitHub 正式版](https://github.com/iebb/mithka/releases/latest) |
| **Linux** (`x64`, `arm64`) | [GitHub 预发布版](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新 GitHub 正式版](https://github.com/iebb/mithka/releases/latest) |
| **HarmonyOS Next** (`.hap`) | [GitHub 预发布版](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新 GitHub 正式版](https://github.com/iebb/mithka/releases/latest) |

iPhone、iPad 与 Mac 共用同一个 App Store 页面，TestFlight 链接同样适用于这三种设备。

### 桌面端安装包说明

- **macOS** 推荐通过 Mac App Store 安装，并由 App Store 自动更新。GitHub 正式版另提供按架构区分的 `.zip` 包；该版本仅做临时签名（ad-hoc）且未经公证，首次启动需在 **系统设置 → 隐私与安全性** 中允许打开。
- **Windows** 同时提供当前用户级 `setup.exe` 安装程序（无需管理员权限，自动注册开始菜单快捷方式与“已安装的应用”）以及 `x64` / `arm64` 便携 ZIP 包。
- **Linux** 同时提供 `x64` / `arm64` AppImage 与便携 tar 包，CI 基于 Ubuntu 24.04 验证启动（执行 `chmod +x Mithka.AppImage` 后在可写目录运行）。
- **Windows 与 Linux 应用内更新**：通过 **设置 → 关于 → 检查更新** 下载对应架构的最新 GitHub 正式版安装包，校验 SHA-256 摘要后原子替换当前安装并自动重启；由系统包管理器、Flatpak 或 Snap 管理的安装会打开下载页而不会直接覆盖外部管理的文件。

---

## 核心特性

- **原生 TDLib 内核与多账号**：通过独立后台 Isolate 运行 `libtdjson` 接收循环，支持多账号快速切换、通行密钥（Passkey）与扫码登录、SOCKS5 / HTTP / MTProto / Web 代理以及加密会话备份与导入。
- **丰富的消息与编辑器**：支持引用回复、表情回应、自定义表情、`.tgs` / `.webm` 动画贴纸、贴纸工坊、GIF、投票、待办清单、定时发送、富文本排版、LaTeX 公式与内联/键盘机器人。
- **多媒体、语音与通话**：支持边下边播全屏视频播放器（画中画与桌面独立播放窗口）、语音与圆形视频消息、接入系统媒体控制的内置音乐播放器，以及一对一和群组语音通话。
- **社群、话题与动态流**：支持聊天分组文件夹、群组话题栏、Telegram 社群（Communities）、限时动态与频道图文视频流、Telegram 小程序（Mini Apps），以及可选的 AI 消息翻译与未读摘要。
- **自研视觉与组件体系**：所有字号、字重、间距、圆角与浅/深色语义调色板均由 `lib/theme/app_theme.dart` 中的具名设计令牌统一管理，统一采用项目自有的 `AppIcon` / `HeroAppIcons` 矢量图标与自定义弹窗组件，不依赖内置 Material 或 Cupertino 图标集。
- **8 种语言本地化**：内置简体中文、繁体中文、英语、日语、韩语、德语、法语和西班牙语。

---

## 为什么叫“Mithka”？

这个名字源于企鹅吉祥物与两个微小质量单位之间的文字游戏：

- 企鹅吉祥物引出 **pengram**：🐧 + *gram*。读作 *penta-gram* 时约为 **5 克**。
- 一 **mithqāl**（مثقال，传统质量单位）等于 **4.6875 克**。

**Mithka** 源自 *mithqāl*——在想象中的天平上，它恰巧比 5 克的（Tele）gram 企鹅还要轻巧一点。

---

## 架构与目录结构

```text
mithka/
├── lib/
│   ├── app/              # 应用外壳、自适应分栏布局、深链路由与桌面多窗口
│   ├── auth/             # 登录流程、多账号存储、扫码与通行密钥认证
│   ├── bot_api/          # Bot API 账号模式与本地兼容适配层
│   ├── call/             # 一对一及群组通话界面与原生音视频桥接
│   ├── channels/         # 话题群导航栏与频道话题视图
│   ├── chat/             # 会话核心（ChatView、ChatViewModel、会话滚动缓存）
│   │   ├── admin/        # 群组/频道资料、成员、管理员权限与管理日志
│   │   ├── ai_translation/ # 可选 AI 翻译与未读消息摘要
│   │   ├── appearance/   # 聊天主题、壁纸与气泡预览
│   │   ├── composer/     # 输入栏、语音/视频录制、投票、清单与富文本编辑器
│   │   ├── links_search/ # t.me/tg:// 链接解析、预览、内置浏览器与会话内搜索
│   │   ├── media/        # 视频播放器、本地流媒体服务、音乐播放与图片编辑
│   │   ├── messages/     # 消息气泡、相册排版、回应、引用回复与操作菜单
│   │   ├── mini_apps/    # Telegram 小程序、机器人平台与账单支付
│   │   └── stickers/     # 贴纸、自定义表情、GIF 与贴纸包制作工坊
│   ├── chats/            # 会话列表、分组文件夹、归档与全局搜索
│   ├── communities/      # Telegram 社群结构与管理界面
│   ├── components/       # 项目自研基础控件、对话框与 AppIcon 图标集
│   ├── config/           # 编译期开关与本地 API 凭据配置
│   ├── contacts/         # 联系人、群组/频道/机器人目录与添加联系人
│   ├── l10n/             # 自动生成的本地化键值与加载器
│   ├── media/            # 相册选择器、相机拍摄与媒体元数据探测
│   ├── moments/          # 动态浏览、发布与频道图文视频流
│   ├── notifications/    # 本地/推送通知与通知范围设置
│   ├── platform/         # 移动与桌面端原生平台通道封装
│   ├── profile/          # 个人/群组资料页、二维码名片与藏品展示
│   ├── security/         # 本地生物识别/密码锁与敏感剪贴板自动清理
│   ├── settings/         # 外观、隐私、存储、代理、AI 与陌生消息过滤设置
│   ├── tdlib/            # Dart FFI 绑定、后台接收 Isolate 与数据模型
│   ├── theme/            # 设计令牌、浅/深色主题调色板与云端主题解析
│   └── update/           # GitHub 版本源与桌面端自更新实现
├── apple/                # iOS 与 macOS 共用的原生 Swift 桥接代码
├── android/ ios/ macos/  # 各移动端与 Apple 桌面端工程及原生插件
├── linux/ windows/ ohos/ # Linux、Windows 与 HarmonyOS Next 平台工程
├── translations/         # 8 语言源 XML 词条目录与校验/生成工具
├── scripts/              # 固定清单的 tdjson 安装脚本与商店发布自动化脚本
└── test/                 # 按领域划分的单元、组件与发布脚本测试套件
```

界面状态基于 `provider` 与按作用域隔离的 `ChangeNotifier` 管理。`lib/tdlib/td_client.dart`
在独立后台 Isolate 中运行阻塞式 `td_receive` 循环，匹配 `@extra` 异步请求并按账号槽位分发强类型事件流，确保主线程渲染始终流畅。

---

## 从源码构建

### 环境要求

- Flutter SDK（固定稳定版本号见 `.github/workflows/quality.yml`）
- 对应目标平台的原生工具链（Xcode、Android SDK、Windows Visual Studio C++ 工具集或 Linux GTK3 开发头文件）
- Python 3（用于下载并校验固定清单的 `tdjson` 预编译库及运行检查脚本）

### 1. 配置 Telegram API 凭据

前往 <https://my.telegram.org> 创建你自己的 `api_id` 与 `api_hash`，复制模板文件并填入凭据（`lib/config/secrets.dart` 已被 `.gitignore` 排除）：

```bash
cp lib/config/secrets_example.dart lib/config/secrets.dart
```

```dart
class Secrets {
  static const int apiId = 123456;
  static const String apiHash = 'your_api_hash';
  static bool get isConfigured => apiId != 0 && apiHash.isNotEmpty;
}
```

*（提示：若保留 `secrets_example.dart` 默认占位值，应用仍可正常编译并启动至凭据引导页，便于单独调试界面或运行组件测试。）*

### 2. 安装预编译 TDLib（`tdjson`）动态库

本仓库无需从源码编译 TDLib。[`scripts/tdjson-manifest.json`](scripts/tdjson-manifest.json)
固定了由 [`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson) 发布的各平台预编译产物及其 SHA-256 校验值：

```bash
# Android（安装至 android/app/src/main/jniLibs/<abi>/）
./scripts/build-tdjson-android.sh arm64-v8a

# iOS（安装 ios/tdjson/tdjson.xcframework 并更新 CocoaPods）
./scripts/build-tdjson-ios.sh
(cd ios && pod install)

# 桌面平台（macos、linux 或 windows；可选架构参数 x64 或 arm64）
./scripts/build-tdjson-desktop.sh macos native-libs/libtdjson.dylib
./scripts/build-tdjson-desktop.sh linux native-libs/libtdjson.so x64
./scripts/build-tdjson-desktop.sh windows native-libs/tdjson.dll x64
```

详细打包位置与磁盘清理说明请参阅 [NATIVE.md](NATIVE.md)。

### 3. 获取依赖并运行

```bash
flutter pub get
flutter run
```

### 可选本地配置

- **Firebase Analytics**：本地开发无需配置。缺少 `android/app/google-services.json` 或 `ios/Runner/GoogleService-Info.plist` 时，应用会自动禁用分析并正常运行。
- **Android 发布签名**：存在 `android/key.properties` 及对应密钥库时使用上传密钥签名，否则回退为调试签名。
- **编译期 API 条款边界**：官方正式版、每夜构建、TestFlight 与各应用商店构建始终保持 `allowTelegramTosViolations = false`（`lib/config/build_flags.dart`）。任何涉及 Telegram API 条款第 1.4 节的代码默认完全不生效，仅在开发者显式传入 `--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true` 自行编译时才会启用（启用该编译开关并不使相关行为符合 Telegram 条款）。

---

## 开发检查与测试

提交更改前，可运行与 CI（`quality.yml`）一致的本地检查：

```bash
# 代码格式与静态分析
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze

# 多语言词条与资源体积检查
python3 translations/tools/check.py
python3 translations/tools/gen_assets.py --check
python3 tool/check_l10n_strings.py
python3 tool/optimize_app_artwork.py --check

# 单元与组件测试套件
flutter test --concurrency=4
```

更多规范请参阅设计令牌说明 [DESIGN.md](DESIGN.md)、本地化文档 [docs/localization.md](docs/localization.md)、测试目录说明 [test/README.md](test/README.md) 以及仓库与协作规范 [AGENTS.md](AGENTS.md)。

---

## 版本管理与自动发布流程

- **`master` 分支维护下一完整次版本号（`X.Y.0`）**：每次推送与 PR 均通过 `Quality` 与各平台构建验证，不直接对外发布安装包。
- **每日自动构建（`sync-nightly.yml`，00:00 UTC / 09:00 东京时间）**：当 `master` 有新提交时，GitHub Actions 将其合并至 `nightly`，将修订号递增一次（`X.Y.1`、`X.Y.2`……；若刚进入新次版本则首次直接发布 `X.Y.0`），并触发多平台 GitHub 预发布版、Google Play 公开测试以及 iOS / macOS TestFlight 上传，绝不将修订号重置为 `.0`。
- **每月两次正式版发布（`weekly-store-release.yml`，每月 1 日与 15 日 09:00 东京时间）**：分配高于当前次版本所有已用版本号的 `store-vX.Y.Z` 标签，使用该确切版本号提交至 App Store（iOS 与 macOS）、Google Play 与 GitHub Releases，并将 HarmonyOS hap 交由华为应用市场 AppGallery 提交（`appgallery-submit.yml`）；随后将 `master` 推进至 `X.(Y+1).0` 并立即触发 `sync-nightly.yml`，使测试渠道当天即可收到 `X.(Y+1).0` 更新。

---

## 许可证与致谢

Mithka 基于 [BSD 3-Clause License](LICENSE) 开源。

TDLib 以及 `third_party/` 目录下的组件分别遵循各自的开源许可证。Mithka 不随应用分发任何第三方应用的专有资源或商标。

## Star 趋势

<a href="https://www.star-history.com/?repos=iebb%2Fmithka&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&theme=dark&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <img alt="Star History 趋势图" src="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
 </picture>
</a>
