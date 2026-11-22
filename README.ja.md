# Mithka

![Mithka — 独立系の Telegram クライアント](docs/images/mithka-github-banner.png)

[English](README.md) | [简体中文](README.zh-CN.md) | 日本語

**Mithka** は、Flutter と Dart FFI 経由の [TDLib](https://core.telegram.org/tdlib) で構築された、
高速でコンパクトなクロスプラットフォームの Telegram クライアントです。Android、iOS、macOS、
Windows、Linux、HarmonyOS Next でネイティブに動作し、スマートフォンでの片手操作から
タブレットやデスクトップのマルチペインのワークスペースまで適応します。

![Mithka のデスクトップ、iPad、iPhone Duo のレイアウトモックアップ](docs/images/mithka-github-devices.png)

*架空の会話を使ったレイアウトのプレビューです。デバイスのフレームはモックアップであり、
実際のスクリーンショットではありません。*

> [!IMPORTANT]
> Mithka は独立した非公式のプロジェクトです。Telegram とは提携しておらず、
> 承認も受けておらず、関係もありません。「Telegram」はその権利者の
> 商標です。
>
> Mithka は Tencent や QQ とも提携しておらず、承認、後援その他の関係も
> ありません。QQ の独自アセットを使用、同梱、複製、再配布することはありません。
> 「Tencent」「QQ」および関連する商標とアセットは、それぞれの
> 所有者に帰属します。
>
> ソースからビルドする場合、Mithka はご自身で用意した API 認証情報を使って
> TDLib 経由で Telegram に接続します。Telegram の
> [利用規約](https://telegram.org/tos)と
> [API 利用規約](https://core.telegram.org/api/terms)に従ってご利用ください。

---

## ダウンロード

| プラットフォーム | ベータ / ナイトリー | 安定版 |
| --- | --- | --- |
| **Android** | [Google Play オープンテスト](https://play.google.com/apps/testing/ad.neko.mithka) · [GitHub の APK](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Google Play](https://play.google.com/store/apps/details?id=ad.neko.mithka) · [GitHub リリース](https://github.com/iebb/mithka/releases/latest) |
| **iOS & iPadOS** | [TestFlight](https://testflight.apple.com/join/tVC8WkbW) | [App Store](https://apps.apple.com/us/app/mithka/id6783830742) |
| **macOS 12+** (`arm64`, `x64`) | [TestFlight](https://testflight.apple.com/join/tVC8WkbW) · [GitHub プレリリース](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Mac App Store](https://apps.apple.com/us/app/mithka/id6783830742?platform=mac) · [GitHub リリース](https://github.com/iebb/mithka/releases/latest) |
| **Windows** (`x64`, `arm64`) | [GitHub プレリリース](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新の GitHub リリース](https://github.com/iebb/mithka/releases/latest) |
| **Linux** (`x64`, `arm64`) | [GitHub プレリリース](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新の GitHub リリース](https://github.com/iebb/mithka/releases/latest) |
| **HarmonyOS Next** (`.hap`) | [GitHub プレリリース](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [最新の GitHub リリース](https://github.com/iebb/mithka/releases/latest) |

iPhone、iPad、Mac は App Store の掲載ページを共有しており、TestFlight のリンクも
この 3 つすべてに対応しています。

### デスクトップ版パッケージに関する注意

- **macOS**: おすすめのインストール方法は Mac App Store 版で、App Store を通じて
  アップデートされます。GitHub リリースではアーキテクチャごとの `.zip`
  アーカイブも配布しています。これらはアドホック署名で公証されていないため、初回起動時に
  **システム設定 → プライバシーとセキュリティ**で許可するよう macOS から求められます。
- **Windows** 版は、ユーザーごとの `setup.exe` インストーラー（管理者
  権限は不要で、スタートメニューのショートカットとインストール済みアプリに登録されます）と、
  `x64` および `arm64` 向けのポータブル ZIP アーカイブの両方を配布しています。
- **Linux** 版は、`x64` と `arm64` の AppImage とポータブルな tarball を配布しており、
  CI で Ubuntu 24.04 に対して検証されています（`chmod +x Mithka.AppImage` を実行し、
  書き込み可能なディレクトリから起動してください）。
- **Windows と Linux のセルフアップデート**: **設定 → 概要 → アップデートを確認**
  を選ぶと、お使いの CPU アーキテクチャ向けの最新の安定版 GitHub リリースを取得し、
  公開されている SHA-256 ダイジェストを検証したうえで、インストールをアトミックに入れ替えて
  再起動します。パッケージマネージャー、Flatpak、Snap でインストールした場合は、外部で管理されているファイルを
  上書きせず、リリースページを開きます。

---

## 主な特長

- **本物の TDLib コアとマルチアカウント対応**: `libtdjson` 上の専用バックグラウンド受信 isolate、
  アカウントの即時切り替え、パスキーと QR コードによるサインイン、SOCKS5 /
  HTTP / MTProto / Web プロキシ、暗号化されたセッションのバックアップとインポートに対応しています。
- **充実したメッセージ機能と入力欄**: 返信、引用、リアクション、カスタム絵文字、
  アニメーションする `.tgs` と `.webm` のステッカー、ステッカースタジオ、GIF、投票、チェックリスト、
  予約送信、リッチテキストの書式設定、LaTeX の数式、インラインボットと返信ボットに対応しています。
- **メディア、音声、通話**: ピクチャーインピクチャーとデスクトップのポップアウトウィンドウに対応した
  ストリーミング対応の全画面動画プレーヤー、ボイスメッセージと丸型ビデオメッセージ、システムの再生中コントロールに対応した
  内蔵ミュージックプレーヤー、1 対 1 およびグループの音声通話を備えています。
- **コミュニティ、トピック、フィード**: チャットフォルダー、フォーラムのトピックバー、Telegram
  Communities、ストーリーとチャンネルの写真・動画フィード、Telegram Mini Apps、そして
  オプションでデバイス上またはユーザーが設定した AI による翻訳と未読の要約に対応しています。
- **意図を持ったデザインシステム**: タイポグラフィ、余白、角の丸み、
  ライト/ダークのパレットを明示的なトークン（`lib/theme/app_theme.dart`）で定義し、独自のモーダル
  ダイアログやコントロール、そして標準の Material や Cupertino のアイコンセットではなくプロジェクト独自のベクターアイコン（`AppIcon` /
  `HeroAppIcons`）を使用しています。
- **8 言語にローカライズ**: 英語、簡体字中国語、繁体字
  中国語、日本語、韓国語、ドイツ語、フランス語、スペイン語に対応しています。

---

## なぜ「Mithka」なのか？

この名前は、ペンギンのマスコットと 2 つのごく小さな質量の単位から着想を得た、
ちょっとした言葉遊びです。

- マスコットから連想されるのは **pengram** です: 🐧 + *gram*。これを *penta-gram* と読むと、
  およそ **5 g** になります。
- 伝統的な質量の単位である **mithqāl**（مثقال）は、1 つで **4.6875 g** です。

*mithqāl* に由来する **Mithka** は、空想の天秤の上で 5 グラムのペンギンより
わずかに軽い、羽のように軽い存在なのです。

---

## アーキテクチャとプロジェクト構成

```text
mithka/
├── lib/
│   ├── app/              # App shell, split-pane layout, deep links, desktop windows
│   ├── auth/             # Login flow, multi-account store, QR & passkey sign-in
│   ├── bot_api/          # Bot API account mode & local TD-compatible adapter
│   ├── call/             # 1-to-1 and group call UI & native VoIP bridges
│   ├── channels/         # Forum/topic navigation and channel topic views
│   ├── chat/             # Conversation core (ChatView, ChatViewModel, session cache)
│   │   ├── admin/        # Chat info, members, permissions, and moderation logs
│   │   ├── ai_translation/ # Optional message translation & unread chat summaries
│   │   ├── appearance/   # Chat themes, wallpapers, and bubble previews
│   │   ├── composer/     # Input bar, voice/video capture, polls, rich composer
│   │   ├── links_search/ # t.me/tg:// router, link previews, internal browser, search
│   │   ├── media/        # Video player, stream server, music player, image editor
│   │   ├── messages/     # Message bubbles, albums, reactions, replies, action menus
│   │   ├── mini_apps/    # Telegram Mini Apps, bot platform, and invoice checkout
│   │   └── stickers/     # Stickers, custom emoji, GIFs, and sticker set studio
│   ├── chats/            # Chat list, folders, archive, and global search
│   ├── communities/      # Telegram Communities hierarchy and management
│   ├── components/       # Project-owned UI primitives, dialogs, and AppIcon set
│   ├── config/           # Build flags and git-ignored API credentials
│   ├── contacts/         # Contacts, groups/channels/bots directory, and add-people
│   ├── l10n/             # Generated localization keys and runtime loader
│   ├── media/            # Asset picker, camera capture, and media metadata probes
│   ├── moments/          # Stories viewer, story authoring, and channel Moments feed
│   ├── notifications/    # Local/push notifications and per-scope mute settings
│   ├── platform/         # Native method-channel bridges across mobile & desktop
│   ├── profile/          # User/chat profiles, QR cards, and collectible gifts
│   ├── security/         # Biometric/passcode lock and auto-clearing clipboard
│   ├── settings/         # Appearance, privacy, storage, proxy, AI, and blocking
│   ├── tdlib/            # Dart FFI bindings, background receive isolate, models
│   ├── theme/            # Design tokens, light/dark palettes, and cloud themes
│   └── update/           # GitHub release feed and Windows/Linux self-updater
├── apple/                # Shared Swift bridges compiled into both iOS and macOS
├── android/ ios/ macos/  # Platform runners and native plugins
├── linux/ windows/ ohos/ # Desktop and HarmonyOS Next runners
├── translations/         # Source XML string catalogues (8 locales) & check tools
├── scripts/              # Manifest-pinned tdjson installers & release automation
└── test/                 # Domain-organized unit, widget, and release-script suites
```

状態管理には `provider` とスコープ付きの `ChangeNotifier` ビューモデルを使用しています。ネイティブの
TDLib 呼び出しが UI の isolate をブロックすることはありません。`lib/tdlib/td_client.dart` は、
ブロッキングする `td_receive` ループを専用のバックグラウンド isolate で実行し、
`@extra` によってリクエストとレスポンスの対応を取り、型付きのアップデートをアカウントスロットごとにブロードキャストします。

---

## ソースからビルド

### 前提条件

- Flutter SDK（固定されている安定版のバージョンは `.github/workflows/quality.yml` を参照してください）
- ターゲット OS 向けのプラットフォームツールチェーン（iOS/macOS では Xcode、Android SDK、
  Windows では Visual Studio の C++ ワークロード、Linux では GTK3 の開発用ヘッダー）
- Python 3（マニフェストで固定された `tdjson` インストーラーと検証ツールで使用します）

### 1. Telegram API の認証情報を設定する

<https://my.telegram.org> からご自身の `api_id` と `api_hash` を取得し、
サンプルファイルをコピーして認証情報を記入します（`lib/config/secrets.dart` は
git で無視されます）。

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

*（ヒント: `secrets_example.dart` を変更しないままでもアプリはコンパイルでき、
起動すると認証情報の設定画面が表示されます。UI だけの作業やウィジェットテストの
実行に便利です。）*

### 2. ビルド済みの TDLib（`tdjson`）バイナリをインストールする

Mithka では TDLib をローカルでコンパイルする必要はありません。
[`scripts/tdjson-manifest.json`](scripts/tdjson-manifest.json) で、
[`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson) で公開されている
SHA-256 で検証済みのビルド済みバイナリを固定しています。

```bash
# Android (installs under android/app/src/main/jniLibs/<abi>/)
./scripts/build-tdjson-android.sh arm64-v8a

# iOS (installs ios/tdjson/tdjson.xcframework, then install pods)
./scripts/build-tdjson-ios.sh
(cd ios && pod install)

# Desktop (macos, linux, or windows; optional arch: x64 or arm64)
./scripts/build-tdjson-desktop.sh macos native-libs/libtdjson.dylib
./scripts/build-tdjson-desktop.sh linux native-libs/libtdjson.so x64
./scripts/build-tdjson-desktop.sh windows native-libs/tdjson.dll x64
```

バンドルの配置の詳細とディスクのクリーンアップのヒントについては、[NATIVE.md](NATIVE.md) を参照してください。

### 3. 依存関係をインストールして実行する

```bash
flutter pub get
flutter run
```

### オプションのローカル設定

- **Firebase Analytics**: ローカルビルドではオプションです。
  `android/app/google-services.json` または `ios/Runner/GoogleService-Info.plist` が
  ない場合、Mithka はアナリティクスを無効にした状態で通常どおりビルド・実行されます。
- **Android のリリース署名**: `android/key.properties` とそのキーストアがあればそれを使用し、
  ない場合はローカルビルド用にデバッグ署名を使用します。
- **コンパイル時の規約境界**: 公式ビルド、ナイトリー、TestFlight、
  ストアリリースは、常に `allowTelegramTosViolations = false`
  （`lib/config/build_flags.dart`）でコンパイルされます。Telegram API 利用規約の
  第 1.4 条に該当するコントリビューターのコードは、
  `--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true` を指定して明示的にセルフビルドしない限り、完全に無効です（これを指定しても、
  その動作が Telegram の規約に準拠するわけではありません）。

---

## 開発と検証

プルリクエストを作成する前に、CI（`quality.yml`）と同じローカルチェックを実行してください。

```bash
# Format & static analysis
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze

# Localization & asset checks
python3 translations/tools/check.py
python3 translations/tools/gen_assets.py --check
python3 tool/check_l10n_strings.py
python3 tool/optimize_app_artwork.py --check

# Unit & widget test suite
flutter test --concurrency=4
```

デザイントークンの規約は [DESIGN.md](DESIGN.md)、ローカライズのワークフローは
[docs/localization.md](docs/localization.md)、テストの構成は
[test/README.md](test/README.md)、リポジトリと PR のルールは
[AGENTS.md](AGENTS.md) にまとめています。

---

## バージョニング、CI、リリース

- **`master` は次のマイナーバージョン（`X.Y.0`）を保持します**: すべての push と PR で
  `Quality` とプラットフォームのビルドワークフローによって検証されますが、ストア向けの成果物を
  直接公開することはありません。
- **毎日のナイトリービルド（`sync-nightly.yml`、00:00 UTC / 09:00 東京）**:
  `master` に新しいコミットがある場合、GitHub Actions が `master` を `nightly` にマージし、
  パッチバージョンを 1 つ上げ（`X.Y.1`、`X.Y.2`、…。新しいマイナーバージョンの最初の同期では `X.Y.0` を配布）、
  マルチプラットフォームの GitHub
  プレリリース、Google Play オープンテスト、iOS/macOS の TestFlight へのアップロードを実行します。パッチ
  番号が `.0` に書き戻されることはありません。
- **月 2 回のストアリリース（`weekly-store-release.yml`、毎月 1 日と 15 日の
  09:00 東京）**: そのマイナーバージョンで使われたすべてのパッチより大きい、変更不可の `store-vX.Y.Z` リリースのタグを付け、
  その正確なバージョンを App Store（iOS と
  macOS）、Google Play、GitHub Releases に提出し、続いて HarmonyOS の hap を
  Huawei AppGallery（`appgallery-submit.yml`）に渡します。その後 `master` を
  `X.(Y+1).0` に進め、すぐに `sync-nightly.yml` を実行して、ベータテスターが
  同じ日に `X.(Y+1).0` を受け取れるようにします。

---

## ライセンスとクレジット

Mithka は [BSD 3-Clause License](LICENSE) の下でライセンスされています。

TDLib と `third_party/` 以下のコンポーネントには、引き続きそれぞれの
ライセンスが適用されます。Mithka は、サードパーティのアプリケーションの独自アセットや商標を配布しません。

## スター履歴

<a href="https://www.star-history.com/?repos=iebb%2Fmithka&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&theme=dark&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
 </picture>
</a>
