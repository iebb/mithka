import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  test('gallery and TGS actions have native Simplified Chinese wording', () {
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.gallerySendOriginal),
      '原图',
    );
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.gallerySendLiveAsVideo),
      '以视频发送',
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
  });

  test('gallery and TGS actions have native Traditional Chinese wording', () {
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.gallerySendOriginal),
      '原圖',
    );
    expect(
      AppStrings.tForLocale('zhHant', AppStringKeys.gallerySendLiveAsVideo),
      '以影片傳送',
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
