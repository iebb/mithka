# Mithka HarmonyOS (ohos) 宿主工程

mithka 的 HarmonyOS NEXT 宿主工程，由鸿蒙 Flutter fork 的 `flutter create --platforms ohos` 生成并定制。Dart 侧构建由 `flutter build hap` 驱动，本目录只包含工程结构与应用配置。

## 环境要求

- 鸿蒙 Flutter fork（openharmony-sig/flutter_flutter）3.44.9+ohos 及以上，需在 PATH 中
- DevEco Studio command-line-tools，SDK API 26 及以上（`DEVECO_SDK_HOME` 指向其 sdk 目录）
- hvigor / ohpm / node（command-line-tools 自带，加入 PATH）

版本低于要求时的典型症状：hvigor 编译 ArkTS 报 `Namespace 'autoFillManager' has no exported member 'AutoFillType'`——这是引擎 embedding 依赖 API 26 类型，升级 command-line-tools 即可。

## 构建

```sh
# 1. 安装 TDLib 原生库（每次检出后一次；从未签名，产物为 unsigned HAP）
./scripts/build-hap.sh

# 2. 构建 HAP
flutter build hap --target-platform ohos-arm64 --release
```

产物路径：`ohos/entry/build/default/outputs/default/entry-default-signed.hap`（未配置签名时为 unsigned 产物，CI 直接使用）。

首次构建前 flutter 工具会在 `ohos/` 下自动生成 `package.json`、`node_modules/`、`oh_modules/` 等本地文件，均已被 .gitignore 忽略。

## 目录说明

- `AppScope/`：应用级配置（bundleName、版本、图标、名称）
- `entry/`：入口 HAP 模块；`entry/libs/arm64-v8a/` 是 tdjson 安装目标
- `hvigorfile.ts` / `hvigor/` / `build-profile.json5`：hvigor 构建配置
