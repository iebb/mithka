# Telegram feature parity implementation — 2026-07-18

This matrix records the Telegram client parity work audited against the
repository's pinned TDLib schema (`tdlib-1.8.66-1b08c83bc078`). It remains
ordered from simpler client interactions (Level 1), through advanced client
and account tools (Level 2), to the requested administration, story, and AI
work. “Implemented” means that a UI entry point and service/request path are
present. Focused tests prove request construction, parsing, policy, or widget
behavior where cited; they do not prove that Telegram accepted the operation
for every account or that a hardware path succeeded on a physical device.

Audit completion checks were green: repository-wide `flutter analyze`, the
21-test deep-link/payment regression batch, the 9-test payment schema/safety
suite, Swift parsing, and a 57/57 comparison against the pinned
`InternalLinkType` constructors.

## Level 1

| # | Feature group | Status | Main implementation evidence |
|---|---|---|---|
| 1 | Rich message cards: polls, checklists, contacts, video notes, shared stories, games, invoices, giveaways, gifts, paid media, suggested posts | Implemented; live payment/provider validation required | `lib/chat/message_special_content.dart`, `lib/chat/message_bubble.dart`, `lib/chat/message_replies_sheet.dart`, `lib/chat/telegram_invoice_checkout_view.dart`, `lib/chat/telegram_payment_service.dart`; `test/rich_message_render_test.dart`, `test/telegram_payment_service_test.dart` |
| 2 | Poll and checklist interactions | Implemented; request/widget tested | `lib/chat/poll_results_view.dart`, `lib/chat/checklist_service.dart`, `lib/chat/checklist_composer_view.dart`; `test/checklist_service_test.dart`, `test/poll_composer_test.dart` |
| 3 | Contact and venue actions | Implemented; live contact/device actions not exercised | `lib/chat/shared_contact_sheet.dart`, `lib/chat/contact_share_picker_view.dart`, `lib/chat/venue_composer_view.dart` |
| 4 | Semantic emoji, sticker, and GIF search plus conversion/export | Implemented; native export needs device validation | `lib/chat/chat_input_bar.dart`, `lib/chat/sticker_export_service.dart`, `lib/chat/sticker_viewer.dart`; `test/sticker_export_service_test.dart`, `test/sticker_viewer_export_menu_test.dart` |
| 5 | Story viewer reactions, replies, sharing, reporting, mute, stealth, and viewers | Implemented; server capability and account gated | `lib/moments/story_viewer_view.dart`, `lib/moments/story_service.dart`; `test/story_service_test.dart` covers story request builders, not a live viewer session |
| 6 | Message info, read times, views, forwards, and Calls | Implemented; live call/device validation pending | `lib/chat/message_info_view.dart`, `lib/call/calls_view.dart`, `lib/call/call_manager.dart`; `test/call_screen_test.dart` |
| 7 | Telegram internal and universal deep links | Implemented for all pinned link constructors; store purchases externally gated | `lib/chat/link_handler.dart`, `lib/chat/telegram_link_details_view.dart`, `lib/chat/telegram_store_purchase_view.dart`, `lib/tdlib/td_requests.dart`; `test/telegram_payment_service_test.dart` covers store preflight/assignment |

## Level 2

| # | Feature group | Status | Main implementation evidence |
|---|---|---|---|
| 8 | Sending controls, effects, paid messages, silent/when-online/scheduled delivery, and scheduled-message editing | Implemented; account/server capability gated | `lib/chat/message_send_options.dart`, `lib/chat/scheduled_messages_view.dart`, `lib/chat/chat_view_model.dart` |
| 9 | Advanced polls and collaborative checklists | Implemented; request/widget tested | `lib/chat/poll_composer_view.dart`, `lib/chat/checklist_service.dart`; `test/poll_composer_test.dart`, `test/checklist_service_test.dart` |
| 10 | Voice and video-message capture, review, pause, cancel, lock, trim, waveform, speed, and transcription | Implemented; physical-device capture/trim validation required | `lib/chat/chat_input_bar.dart`, `lib/chat/voice_note_preview_view.dart`, `lib/chat/voice_note_trimmer.dart`, `lib/chat/video_note_recorder_view.dart`, `lib/chat/video_note_preview_view.dart`, `lib/chat/video_trim_service.dart`, `lib/chat/message_bubble.dart`; `test/voice_note_preview_test.dart`, `test/video_note_recorder_test.dart`, `test/video_trim_service_test.dart` |
| 11 | Modern media quality modes, live/motion photos, image editing, video cover/start/trim, and albums | Implemented; physical-device media-library and codec validation required | `lib/chat/gallery_send_mode_sheet.dart`, `lib/chat/media_send_preview_view.dart`, `lib/chat/image_edit_view.dart`, `lib/media/app_asset_picker.dart`; `test/gallery_send_mode_sheet_test.dart`, `test/app_asset_picker_test.dart`, `test/video_trim_service_test.dart` |
| 12 | Saved Messages topics and navigation | Implemented; request tested | `lib/chat/saved_messages_service.dart`, `lib/chat/saved_messages_view.dart`; `test/saved_messages_service_test.dart` |
| 13 | Chat folders and folder management | Implemented; request/widget tested | `lib/settings/chat_folder_service.dart`, `lib/settings/chat_folder_management_view.dart`; `test/chat_folder_service_test.dart`, `test/chat_folder_membership_view_test.dart` |
| 14 | Public chat, user, post, and hashtag discovery | Implemented; Telegram limits/account eligibility apply | `lib/chats/public_discovery_service.dart`, `lib/chats/public_discovery_view.dart`, `lib/chats/search_view.dart`; `test/public_discovery_service_test.dart` |
| 15 | Authentication and account security | Implemented; passkey/biometric/store entitlements need live validation | `lib/auth/auth_manager.dart`, `lib/auth/telegram_passkey_service.dart`, `lib/settings/account_security_service.dart`, `lib/security/local_app_lock_controller.dart`; `test/auth_state_transition_test.dart`, `test/telegram_passkey_service_test.dart`, `test/account_security_service_test.dart`, `test/local_app_lock_controller_test.dart` |
| 16 | Telegram Business tools | Implemented; Premium, account, and server capability gated | `lib/settings/business_service.dart`, `lib/settings/business_tools_views.dart`, `lib/settings/business_settings_view.dart`; `test/business_service_test.dart` |
| 17 | Bots, inline mode, Mini Apps, permissions, invoices, QR, sharing, emoji status, stories, messages, and guest queries | Implemented; provider/device/account gated | `lib/chat/bot_platform_service.dart`, `lib/chat/telegram_mini_app_platform.dart`, `lib/chat/telegram_mini_app_view.dart`, `lib/chat/telegram_invoice_checkout_view.dart`; `test/bot_platform_service_test.dart`, `test/telegram_mini_app_platform_test.dart`, `test/telegram_payment_service_test.dart` |
| 18 | Sticker and custom-emoji creation and set management | Implemented; account eligibility and media-format limits apply | `lib/chat/sticker_set_management_service.dart`, `lib/chat/sticker_set_studio_view.dart`; `test/sticker_set_management_service_test.dart`, `test/sticker_admin_surface_style_test.dart` |
| 19 | Storage, network, download, and auto-download management | Implemented; destructive cache effects need device validation | `lib/settings/data_storage_service.dart`, `lib/settings/storage_usage_view.dart`, `lib/settings/network_usage_view.dart`, `lib/settings/downloads_view.dart`, `lib/settings/auto_download_settings_view.dart`; `test/data_storage_service_test.dart` |
| 20 | Profile and contact management | Implemented; account rights and photo-picker validation apply | `lib/profile/profile_contact_service.dart`, `lib/profile/profile_contact_management_view.dart`, `lib/profile/profile_photo_management_view.dart`; `test/profile_contact_service_test.dart`, `test/profile_photo_policy_test.dart` |

### Payment and deep-link scope notes

- **1:** Invoice cards open an owned checkout that covers order information,
  shipping options, tips, terms, Stars, saved credentials with a temporary
  password, new Stripe credentials, provider-WebView `payment_form_submit`,
  `sendPaymentForm`, and HTTPS verification/pending handling.
- **7:** Each of the 57 `InternalLinkType` constructors in the pinned schema has
  an explicit handler. Premium gift, Stars, and restore-purchase links run
  `canPurchaseFromStore` before StoreKit; an unauthorized client stops on an
  owned dependency explanation before any charge begins.
- **8:** Paid-message sending uses Telegram's message send options and is
  independent of invoice checkout and store-product purchase flows.
- **17:** Mini App invoices report paid, cancelled, failed, or pending from the
  real checkout result. Home-screen shortcut installation remains explicitly
  unsupported, and Smart Glocal native tokenization is not bundled.

## Requested advanced items

| # | Feature group | Status | Main implementation evidence |
|---|---|---|---|
| 21 | Group and channel administration | Implemented for audited administration surfaces; privilege/account gated | `lib/chat/group_administration_service.dart`, `lib/chat/group_administration_view.dart`, existing member/admin/topic/statistics views; `test/group_administration_service_test.dart` |
| 22 | Channel direct messages and suggested posts | Implemented; eligible-channel/server role gated | `lib/chat/channel_direct_messages_service.dart`, `lib/chat/channel_direct_messages_view.dart`; `test/channel_direct_messages_service_test.dart` |
| 23 | Story authoring and management | Implemented within pinned schema; device/account gated | `lib/moments/story_authoring_view.dart`, `lib/moments/story_area_editor_view.dart`, `lib/moments/story_management_view.dart`, `lib/moments/story_media_preparer.dart`, `lib/moments/story_service.dart`; `test/story_service_test.dart`, `test/story_surface_style_test.dart` |
| 30 | Telegram AI composition, styles, summaries, voice/video-message transcription, and capability gating | Implemented; Telegram server capability/Premium limits apply | `lib/chat/telegram_ai_service.dart`, `lib/chat/telegram_ai_editor_view.dart`, `lib/chat/chat_view_model.dart`, `lib/chat/message_bubble.dart`; `test/telegram_ai_service_test.dart`, `test/telegram_ai_surface_style_test.dart` |

### Advanced-item scope notes

- **21:** The audited administration surface covers profile description/photo,
  slow mode, reactions, discussion linking, signed messages, hidden members,
  anti-spam, automatic translation, history/forum toggles, invite links and
  join requests, forum topics, statistics, and boost/status discovery. The
  giveaway panel reads Telegram option and prepaid-record availability; it does
  not claim an in-app giveaway checkout or launch workflow.
- **22:** The audited surface covers direct-message topic loading/history,
  drafts, text and attachment sending, replies, topic controls, and
  server-authorized suggested-post compose/edit/approve/decline actions.
- **23:** The audited surface covers camera/gallery photo and video input,
  long-video segmentation, image editing, cover timestamps, captions/entities,
  privacy and posting targets, movable/resizable/rotatable story areas,
  profile/archive/pin operations, albums, and RTMP Live Story controls. It does
  not claim scheduled stories, saved story drafts, or a source-less in-app Live
  Story camera because those operations are absent from the pinned schema.
- **30:** This is a Telegram-server integration, not an on-device AI model. The
  UI and request paths cover proofreading/composition, translation, emoji
  addition, built-in and custom styles, message summaries, and
  `recognizeSpeech` for eligible voice/video messages. Runtime TDLib options and
  per-message capability fields decide whether each action is shown.

## TGS custom-emoji and sticker export

The custom-emoji/sticker preview menu offers **Lottie JSON** only when the
source is an animated `.tgs` sticker. The export decompresses the original
gzip payload, validates required Lottie fields, and writes the original JSON
to Files. Static stickers, photos, and WEBM video stickers never show this
option. Existing preview exports to PNG/APNG, GIF, and supported MOV remain
available.

Implementation: `lib/chat/sticker_export_service.dart` and
`lib/chat/sticker_viewer.dart`.

## External and pinned-schema constraints

- This audit inspected source and focused Flutter tests. It did not use a live
  Telegram production account, complete a store transaction, place a peer call,
  or run camera, microphone, biometric, notification, and media flows on a
  physical device.
- Passkeys require production Associated Domains / AASA on Apple platforms and
  Digital Asset Links on Android. StoreKit Premium auth also needs the live
  product, receipt, and Telegram account response.
- `canPurchaseFromStore` and `assignStoreTransaction` are restricted by
  Telegram server authorization. Premium gifts, Stars, and restore flows also
  require Apple developer-owned product identifiers and live SKU availability;
  Android still needs a Google Play Billing purchase-token adapter. StoreKit
  preflight happens before purchase, and a failed receipt assignment can retry
  the same receipt without initiating a second charge.
- Ordinary bot-invoice checkout has app paths for Stars, saved credentials,
  native Stripe tokenization, and provider web forms. Smart Glocal requires its
  native SDK. A 3DS/provider verification URL exits the current checkout as
  pending because the pinned TDLib response has no later completion callback;
  live merchant and physical-device validation is still required.
- Message read dates, viewer identities, story interactions, public-post
  searches, Business features, bot/Mini App capabilities, administration
  controls, channel direct messages, and Telegram AI actions are shown only
  when TDLib and the current account expose the corresponding capability.
- Group/channel administration still requires the exact owner or administrator
  rights checked by Telegram. Direct-message topics and suggested-post actions
  additionally require an eligible channel and server-provided action flags.
- In-app Live Story creation is exposed as RTMP only. Starting a source-less
  camera stream is intentionally not offered; the pinned schema has no story
  draft or scheduled-story API.
- Story links and stealth mode may require Premium. Posting destinations,
  privacy choices, interactions, archive/pin controls, albums, and Live Story
  controls remain subject to `canPostStory` and per-story capability fields.
- Telegram AI composition, custom styles, summaries, and speech recognition are
  server operations. Availability, quotas, supported languages, and Premium
  requirements are authoritative server responses rather than local model
  guarantees.
- Telegram and TDLib remain the authoritative validators for TGS feature
  support and WEBM codec, alpha, audio-track, duration, and dimension limits.
- The video trimmer, sticker conversion/export, camera recorders, photo library,
  live/motion-photo extraction, call media engine, QR scanner, Mini App motion,
  location, secure storage, and biometrics cross plugin or native boundaries.
  Focused tests validate their Dart contracts or request payloads, not every
  OS/device implementation.
- Camera, microphone, passkey, purchase, notification, and media-library paths
  still require normal physical-device permission and entitlement validation.
