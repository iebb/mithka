import 'package:flutter/widgets.dart';

import 'app_icons.dart';

enum DocumentFilePalette { blue, green, red, yellow }

extension DocumentFilePaletteColor on DocumentFilePalette {
  Color get color => switch (this) {
    DocumentFilePalette.blue => const Color(0xFF5CAFEB),
    DocumentFilePalette.green => const Color(0xFF68C36A),
    DocumentFilePalette.red => const Color(0xFFF16E66),
    DocumentFilePalette.yellow => const Color(0xFFEFC95A),
  };
}

class DocumentFileVisual {
  const DocumentFileVisual({required this.palette, required this.label});

  final DocumentFilePalette palette;
  final String label;

  Color get color => palette.color;
}

/// Matches Telegram's four folded-document color buckets. Unknown file types
/// are assigned from their first extension character instead of appearing gray.
DocumentFileVisual documentFileVisualFor({
  required String fileName,
  required String extension,
}) {
  final normalizedExtension = _normalizedExtension(fileName, extension);
  final palette = switch (normalizedExtension) {
    'doc' || 'docx' || 'txt' || 'psd' => DocumentFilePalette.blue,
    'xls' || 'xlsx' || 'csv' => DocumentFilePalette.green,
    'pdf' || 'ppt' || 'pptx' || 'key' => DocumentFilePalette.red,
    'zip' ||
    'rar' ||
    'ai' ||
    'mp3' ||
    'mov' ||
    'avi' => DocumentFilePalette.yellow,
    _ => _fallbackPalette(normalizedExtension, fileName),
  };
  return DocumentFileVisual(palette: palette, label: normalizedExtension);
}

class DocumentFileIcon extends StatelessWidget {
  const DocumentFileIcon({
    super.key,
    required this.fileName,
    required this.extension,
    this.size = 40,
  });

  final String fileName;
  final String extension;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visual = documentFileVisualFor(
      fileName: fileName,
      extension: extension,
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AppIcon(HeroAppIcons.solidFile, size: size, color: visual.color),
          if (visual.label.isNotEmpty)
            Positioned(
              left: size * 0.14,
              right: size * 0.14,
              bottom: size * 0.18,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  visual.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: const Color(0xFFFFFFFF),
                    fontSize: size * 0.35,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _normalizedExtension(String fileName, String extension) {
  var value = extension.trim();
  while (value.startsWith('.')) {
    value = value.substring(1);
  }
  if (value.contains('.')) {
    value = value.substring(value.lastIndexOf('.') + 1);
  }
  if (value.isEmpty) {
    final trimmedName = fileName.trim();
    final dot = trimmedName.lastIndexOf('.');
    if (dot >= 0 && dot + 1 < trimmedName.length) {
      value = trimmedName.substring(dot + 1);
    }
  }
  return value.toLowerCase();
}

DocumentFilePalette _fallbackPalette(String extension, String fileName) {
  final source = extension.isNotEmpty
      ? extension
      : fileName.trim().toLowerCase();
  if (source.isEmpty) return DocumentFilePalette.blue;
  return DocumentFilePalette.values[source.codeUnitAt(0) % 4];
}
