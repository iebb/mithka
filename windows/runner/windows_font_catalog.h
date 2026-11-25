#ifndef RUNNER_WINDOWS_FONT_CATALOG_H_
#define RUNNER_WINDOWS_FONT_CATALOG_H_

#include <string>
#include <vector>

struct WindowsFontEntry {
  std::string family;
  std::string display_name;
  bool is_monospace = false;
};

// Enumerates locally installed font families from DirectWrite.
std::vector<WindowsFontEntry> LoadWindowsSystemFonts();

// Resolves family names (including localized names or mixed case) to DirectWrite
// canonical en-us family names. Unrecognized names map to empty strings.
std::vector<std::string> NormalizeWindowsFontFamilies(
    const std::vector<std::string>& families);

#endif  // RUNNER_WINDOWS_FONT_CATALOG_H_
