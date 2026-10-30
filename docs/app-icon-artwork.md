# App icon artwork and packaging

Reuse existing artwork before adding another source. Icon identities and native
alternate-icon names are compatibility data: keep previously selected icons
available even when they are no longer offered in the picker.

The Flutter picker uses transparent WebP tiles with a maximum edge of 256px
for the 48 penguin icons and the legacy identities. Non-square legacy artwork
keeps its aspect ratio. Pixel artwork uses nearest-neighbor resizing and
lossless WebP. Native launcher artwork keeps its original canvas size and
transparency; do not resize the 1024px iOS sources.

The nine standard icons are previewed with their real backgrounds from opaque
256px WebPs, `picker/standard-<launcher file>.webp` (light and `_dark`
versions, about 44 KB in total), read through `AppIconVariant.previewAsset`.
They are made from the launcher PNGs with Lanczos resizing, or
nearest-neighbor and lossless WebP for pixel artwork. Regenerate them whenever
a standard launcher PNG changes.

Only the eleven PNGs supported by `MacOSAppIconPlugin` enter the macOS Flutter
bundle. iOS uses its native icon catalogue and Icon Composer files; Android uses
its launcher resources. Neither mobile platform needs another copy of every
full-size launcher PNG in `flutter_assets`.

Run `python3 tool/optimize_app_artwork.py --write` after adding artwork. This
requires pngquant, cwebp and Pillow. It compresses identical PNG inputs once and
writes the same bytes to their existing native/source paths, then converts new
picker PNGs to WebP. PNG quantization has a quality floor and keeps the original
when that floor cannot be met. Commit the resulting assets and picker paths.
CI runs the dependency-free `--check` byte and dimension budgets.

The Runner target uses `ASSETCATALOG_COMPILER_OPTIMIZATION = space` for all
configurations. All alternate icons remain included. See Apple's
[asset catalogue build settings](https://developer.apple.com/documentation/Xcode/build-settings-reference).

## Size investigation

The CI IPAs for 1.7.11 and 1.8.8 were 79.46 and 130.45 MiB respectively. Their
compressed `Assets.car` contributions were 15.25 and 55.46 MiB; Flutter assets
grew from 2.87 to 13.47 MiB. The main app/engine/TDLib binaries were essentially
unchanged. These are IPA measurements, not App Store download estimates: store
thinning and signing change the final download.

The optimization of the larger master catalogue reduces picker sources from
7,947,623 to 579,782 bytes, launcher PNG sources from 45,959,823 to 12,230,371
bytes, native catalogue PNGs from 45,386,735 to 12,087,813 bytes, and Icon Composer
layers from 22,953,703 to 6,770,931 bytes. All 60 icon identities remain available.
The production Flutter asset builder confirms that iOS/Android bundle the
shared picker WebPs and no full launcher PNGs; macOS additionally includes its
eleven Dock PNGs. MaterialIcons is disabled and absent from the audited IPA.

A credential-free actool comparison of the complete master catalogue (iPhone
and iPad, deployment target iOS 15, all alternate icons) reduces `Assets.car`
from 349,568,200 to 256,157,528 bytes with optimized inputs and `space` compilation.
Both results retain 59 alternates plus the primary icon for each device family.
These unthinned compiler outputs are useful for comparison, not download claims.
