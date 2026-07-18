import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  test('gallery and TGS actions have native Simplified Chinese wording', () {
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.gallerySendHdTitle),
      '高清画质',
    );
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.gallerySendMotionSubtitle),
      '将动态部分作为视频发送',
    );
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.stickerStudioFormatTgs),
      '矢量动画 · 最大 64 KB',
    );
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.profilePhotoSetAsAvatar),
      '设为头像',
    );
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.savedMessages),
      '保存的消息',
    );
    expect(
      AppStrings.tForLocale(
        'zhHans',
        AppStringKeys.appearanceSavedMessagesBookmarkView,
      ),
      '保存的消息书签视图',
    );
  });

  test('gallery and TGS actions have native Traditional Chinese wording', () {
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.gallerySendHdTitle),
      '高畫質',
    );
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.gallerySendMotionSubtitle),
      '將動態部分作為影片傳送',
    );
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.stickerStudioValidationTgs),
      '所選檔案不是有效的 gzip 壓縮 TGS 動畫。',
    );
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.profilePhotoSetAsAvatar),
      '設為頭像',
    );
  });

  test('call history is localized in every non-English locale', () {
    const locales = ['de', 'es', 'fr', 'ja', 'ko', 'zhHans', 'zhHant'];
    for (final locale in locales) {
      expect(
        AppStrings.tForLocale(locale, AppStringKeys.callsTitle),
        isNot('Calls'),
        reason: locale,
      );
      expect(
        AppStrings.tForLocale(locale, AppStringKeys.callsLoadFailed),
        isNot('Couldn’t load call history'),
        reason: locale,
      );
      expect(
        AppStrings.tForLocale(locale, AppStringKeys.callsRetry),
        isNot('Try again'),
        reason: locale,
      );
    }
  });
}
