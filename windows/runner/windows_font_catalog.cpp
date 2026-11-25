#include "windows_font_catalog.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <dwrite_1.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <limits>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

bool IsAsciiSpace(unsigned char ch) {
  return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\v' ||
         ch == '\f';
}

char ToLowerAsciiChar(unsigned char ch) {
  if (ch >= 'A' && ch <= 'Z') {
    return static_cast<char>(ch - 'A' + 'a');
  }
  return static_cast<char>(ch);
}

std::string ToLowerAsciiString(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char ch) { return ToLowerAsciiChar(ch); });
  return value;
}

std::string Utf16ToUtf8(const std::wstring& input) {
  if (input.empty() ||
      input.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return {};
  }
  const int input_len = static_cast<int>(input.size());
  const int required = ::WideCharToMultiByte(
      CP_UTF8, 0, input.data(), input_len, nullptr, 0, nullptr, nullptr);
  if (required <= 0) {
    return {};
  }
  std::string output(static_cast<size_t>(required), '\0');
  const int written = ::WideCharToMultiByte(
      CP_UTF8, 0, input.data(), input_len, output.data(), required, nullptr,
      nullptr);
  if (written <= 0) {
    return {};
  }
  output.resize(static_cast<size_t>(written));
  return output;
}

std::wstring Utf8ToUtf16(const std::string& input) {
  if (input.empty() || input.find('\0') != std::string::npos ||
      input.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return {};
  }
  const int input_len = static_cast<int>(input.size());
  const int required = ::MultiByteToWideChar(
      CP_UTF8, 0, input.data(), input_len, nullptr, 0);
  if (required <= 0) {
    return {};
  }
  std::wstring output(static_cast<size_t>(required), L'\0');
  const int written = ::MultiByteToWideChar(
      CP_UTF8, 0, input.data(), input_len, output.data(), required);
  if (written <= 0) {
    return {};
  }
  output.resize(static_cast<size_t>(written));
  return output;
}

std::string TrimUtf8(const std::string& value) {
  if (value.find('\0') != std::string::npos) {
    return {};
  }
  size_t start = 0;
  while (start < value.size() &&
         IsAsciiSpace(static_cast<unsigned char>(value[start]))) {
    ++start;
  }
  size_t end = value.size();
  while (end > start &&
         IsAsciiSpace(static_cast<unsigned char>(value[end - 1]))) {
    --end;
  }
  return value.substr(start, end - start);
}

std::string ToLowerUtf8(const std::string& value) {
  const std::wstring wide = Utf8ToUtf16(value);
  if (wide.empty() ||
      wide.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return ToLowerAsciiString(value);
  }
  const int wide_len = static_cast<int>(wide.size());
  const int required = ::LCMapStringEx(
      LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE, wide.data(), wide_len, nullptr, 0,
      nullptr, nullptr, 0);
  if (required <= 0) {
    return ToLowerAsciiString(value);
  }
  std::wstring lowered(static_cast<size_t>(required), L'\0');
  const int written = ::LCMapStringEx(
      LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE, wide.data(), wide_len,
      lowered.data(), required, nullptr, nullptr, 0);
  if (written <= 0) {
    return ToLowerAsciiString(value);
  }
  lowered.resize(static_cast<size_t>(written));
  std::string utf8_lowered = Utf16ToUtf8(lowered);
  return utf8_lowered.empty() ? ToLowerAsciiString(value) : utf8_lowered;
}

bool EqualsIgnoreCaseAscii(const std::string& a, const std::string& b) {
  if (a.size() != b.size()) {
    return false;
  }
  for (size_t i = 0; i < a.size(); ++i) {
    if (ToLowerAsciiChar(static_cast<unsigned char>(a[i])) !=
        ToLowerAsciiChar(static_cast<unsigned char>(b[i]))) {
      return false;
    }
  }
  return true;
}

bool ContainsIgnoreCaseWide(const std::wstring& haystack,
                            const wchar_t* needle) {
  if (!needle || *needle == L'\0') {
    return false;
  }
  const size_t needle_len = ::wcslen(needle);
  if (haystack.size() < needle_len) {
    return false;
  }
  for (size_t i = 0; i + needle_len <= haystack.size(); ++i) {
    if (::_wcsnicmp(haystack.c_str() + i, needle, needle_len) == 0) {
      return true;
    }
  }
  return false;
}

std::wstring ReadLocalizedStringAt(IDWriteLocalizedStrings* strings,
                                   UINT32 index) {
  if (!strings) {
    return {};
  }
  UINT32 length = 0;
  if (FAILED(strings->GetStringLength(index, &length)) || length == 0) {
    return {};
  }
  std::wstring buffer(static_cast<size_t>(length) + 1, L'\0');
  if (FAILED(strings->GetString(index, buffer.data(), length + 1))) {
    return {};
  }
  buffer.resize(length);
  return buffer;
}

std::string ResolveCanonicalFamilyName(IDWriteLocalizedStrings* names) {
  if (!names) {
    return {};
  }
  const UINT32 count = names->GetCount();
  if (count == 0) {
    return {};
  }
  UINT32 index = 0;
  BOOL exists = FALSE;
  if (SUCCEEDED(names->FindLocaleName(L"en-us", &index, &exists)) && exists) {
    const std::string resolved =
        TrimUtf8(Utf16ToUtf8(ReadLocalizedStringAt(names, index)));
    if (!resolved.empty()) {
      return resolved;
    }
  }
  return TrimUtf8(Utf16ToUtf8(ReadLocalizedStringAt(names, 0)));
}

std::vector<std::wstring> BuildUserDisplayLocaleCandidates() {
  wchar_t user_locale_buf[LOCALE_NAME_MAX_LENGTH] = {};
  std::vector<std::wstring> candidates;
  if (::GetUserDefaultLocaleName(user_locale_buf, LOCALE_NAME_MAX_LENGTH) <= 0) {
    return candidates;
  }
  std::wstring user_locale = user_locale_buf;
  if (user_locale.empty()) {
    return candidates;
  }
  candidates.push_back(user_locale);
  if (::_wcsnicmp(user_locale.c_str(), L"zh", 2) == 0) {
    const bool traditional =
        ContainsIgnoreCaseWide(user_locale, L"TW") ||
        ContainsIgnoreCaseWide(user_locale, L"HK") ||
        ContainsIgnoreCaseWide(user_locale, L"MO") ||
        ::_wcsnicmp(user_locale.c_str(), L"zh-Hant", 7) == 0;
    if (traditional) {
      candidates.emplace_back(L"zh-tw");
      candidates.emplace_back(L"zh-hk");
      candidates.emplace_back(L"zh-hant");
    } else {
      candidates.emplace_back(L"zh-cn");
      candidates.emplace_back(L"zh-hans");
    }
  }
  return candidates;
}

bool TryFindFirstMatchingLocale(IDWriteLocalizedStrings* names,
                                const std::vector<std::wstring>& locales,
                                UINT32* out_index) {
  for (const auto& locale : locales) {
    if (locale.empty()) {
      continue;
    }
    UINT32 index = 0;
    BOOL exists = FALSE;
    if (SUCCEEDED(names->FindLocaleName(locale.c_str(), &index, &exists)) &&
        exists) {
      *out_index = index;
      return true;
    }
  }
  return false;
}

std::string ResolveDisplayFamilyName(
    IDWriteLocalizedStrings* names,
    const std::vector<std::wstring>& locale_candidates,
    const std::string& canonical_family) {
  if (!names || names->GetCount() == 0 || locale_candidates.empty()) {
    return canonical_family;
  }
  UINT32 index = 0;
  if (TryFindFirstMatchingLocale(names, locale_candidates, &index)) {
    const std::string localized =
        TrimUtf8(Utf16ToUtf8(ReadLocalizedStringAt(names, index)));
    if (!localized.empty()) {
      return localized;
    }
  }
  return canonical_family;
}

bool IsExcludedIconOrSymbolFamily(const std::string& canonical_family) {
  static constexpr std::array<const char*, 9> kExcludedFamilies = {
      "HoloLens MDL2 Assets",
      "Marlett",
      "MT Extra",
      "Segoe Fluent Icons",
      "Segoe MDL2 Assets",
      "Webdings",
      "Wingdings",
      "Wingdings 2",
      "Wingdings 3",
  };
  for (const char* excluded : kExcludedFamilies) {
    if (EqualsIgnoreCaseAscii(canonical_family, excluded)) {
      return true;
    }
  }
  return false;
}

bool IsUserUsableFontFamily(IDWriteFontFamily* font_family,
                            const std::string& canonical_family) {
  if (!font_family || canonical_family.empty() ||
      canonical_family.front() == '@' ||
      IsExcludedIconOrSymbolFamily(canonical_family)) {
    return false;
  }
  ComPtr<IDWriteFont> representative_font;
  if (FAILED(font_family->GetFirstMatchingFont(
          DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
          DWRITE_FONT_STYLE_NORMAL, representative_font.GetAddressOf())) ||
      !representative_font) {
    if (font_family->GetFontCount() == 0 ||
        FAILED(font_family->GetFont(0, representative_font.GetAddressOf())) ||
        !representative_font) {
      return false;
    }
  }
  return representative_font->IsSymbolFont() != TRUE;
}

ComPtr<IDWriteFontCollection> OpenSystemFontCollection() {
  ComPtr<IDWriteFactory> factory;
  if (FAILED(::DWriteCreateFactory(
          DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
          reinterpret_cast<IUnknown**>(factory.GetAddressOf()))) ||
      !factory) {
    return nullptr;
  }
  ComPtr<IDWriteFontCollection> collection;
  if (FAILED(factory->GetSystemFontCollection(collection.GetAddressOf(), TRUE)) ||
      !collection) {
    return nullptr;
  }
  return collection;
}

std::unordered_map<std::string, std::string> BuildAliasLookup(
    IDWriteFontCollection* collection) {
  std::unordered_map<std::string, std::string> alias_to_canonical;
  const UINT32 family_count = collection->GetFontFamilyCount();
  alias_to_canonical.reserve(static_cast<size_t>(family_count) * 2);

  for (UINT32 i = 0; i < family_count; ++i) {
    ComPtr<IDWriteFontFamily> font_family;
    if (FAILED(collection->GetFontFamily(i, font_family.GetAddressOf())) ||
        !font_family) {
      continue;
    }
    ComPtr<IDWriteLocalizedStrings> family_names;
    if (FAILED(font_family->GetFamilyNames(family_names.GetAddressOf())) ||
        !family_names) {
      continue;
    }
    const std::string canonical = ResolveCanonicalFamilyName(family_names.Get());
    if (!IsUserUsableFontFamily(font_family.Get(), canonical)) {
      continue;
    }
    const UINT32 name_count = family_names->GetCount();
    for (UINT32 j = 0; j < name_count; ++j) {
      const std::string localized =
          TrimUtf8(Utf16ToUtf8(ReadLocalizedStringAt(family_names.Get(), j)));
      if (!localized.empty()) {
        alias_to_canonical.emplace(ToLowerUtf8(localized), canonical);
      }
    }
  }
  return alias_to_canonical;
}

struct SortableFontEntry {
  WindowsFontEntry entry;
  std::string sort_key;
};

}  // namespace

std::vector<WindowsFontEntry> LoadWindowsSystemFonts() {
  ComPtr<IDWriteFontCollection> collection = OpenSystemFontCollection();
  if (!collection) {
    return {};
  }

  const std::vector<std::wstring> locale_candidates =
      BuildUserDisplayLocaleCandidates();
  const UINT32 family_count = collection->GetFontFamilyCount();
  std::vector<SortableFontEntry> collected;
  collected.reserve(family_count);
  std::unordered_set<std::string> seen_families;

  for (UINT32 i = 0; i < family_count; ++i) {
    ComPtr<IDWriteFontFamily> font_family;
    if (FAILED(collection->GetFontFamily(i, font_family.GetAddressOf())) ||
        !font_family) {
      continue;
    }

    ComPtr<IDWriteLocalizedStrings> family_names;
    if (FAILED(font_family->GetFamilyNames(family_names.GetAddressOf())) ||
        !family_names) {
      continue;
    }

    const std::string canonical = ResolveCanonicalFamilyName(family_names.Get());
    if (canonical.empty() || canonical.front() == '@' ||
        IsExcludedIconOrSymbolFamily(canonical)) {
      continue;
    }

    ComPtr<IDWriteFont> representative_font;
    if (FAILED(font_family->GetFirstMatchingFont(
            DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
            DWRITE_FONT_STYLE_NORMAL, representative_font.GetAddressOf())) ||
        !representative_font) {
      if (font_family->GetFontCount() == 0 ||
          FAILED(font_family->GetFont(0, representative_font.GetAddressOf())) ||
          !representative_font) {
        continue;
      }
    }

    if (representative_font->IsSymbolFont() == TRUE) {
      continue;
    }

    std::string lowered_key = ToLowerUtf8(canonical);
    if (!seen_families.insert(lowered_key).second) {
      continue;
    }

    bool is_monospace = false;
    ComPtr<IDWriteFont1> font1;
    if (SUCCEEDED(representative_font.As(&font1)) && font1) {
      is_monospace = (font1->IsMonospacedFont() == TRUE);
    }

    SortableFontEntry item;
    item.entry.family = canonical;
    item.entry.display_name = ResolveDisplayFamilyName(
        family_names.Get(), locale_candidates, canonical);
    item.entry.is_monospace = is_monospace;
    item.sort_key = std::move(lowered_key);
    collected.push_back(std::move(item));
  }

  std::sort(collected.begin(), collected.end(),
            [](const SortableFontEntry& lhs, const SortableFontEntry& rhs) {
              return lhs.sort_key < rhs.sort_key;
            });

  std::vector<WindowsFontEntry> entries;
  entries.reserve(collected.size());
  for (auto& item : collected) {
    entries.push_back(std::move(item.entry));
  }
  return entries;
}

std::vector<std::string> NormalizeWindowsFontFamilies(
    const std::vector<std::string>& families) {
  std::vector<std::string> normalized(families.size());
  std::vector<std::string> trimmed_inputs(families.size());
  bool has_non_empty = false;
  for (size_t i = 0; i < families.size(); ++i) {
    trimmed_inputs[i] = TrimUtf8(families[i]);
    if (!trimmed_inputs[i].empty()) {
      has_non_empty = true;
    }
  }
  if (!has_non_empty) {
    return normalized;
  }

  ComPtr<IDWriteFontCollection> collection = OpenSystemFontCollection();
  if (!collection) {
    return normalized;
  }

  bool alias_map_built = false;
  std::unordered_map<std::string, std::string> alias_to_canonical;

  for (size_t i = 0; i < trimmed_inputs.size(); ++i) {
    const std::string& trimmed = trimmed_inputs[i];
    if (trimmed.empty()) {
      continue;
    }

    const std::wstring wide = Utf8ToUtf16(trimmed);
    if (wide.empty()) {
      continue;
    }

    UINT32 index = 0;
    BOOL exists = FALSE;
    if (SUCCEEDED(collection->FindFamilyName(wide.c_str(), &index, &exists)) &&
        exists) {
      ComPtr<IDWriteFontFamily> font_family;
      if (SUCCEEDED(collection->GetFontFamily(index, font_family.GetAddressOf())) &&
          font_family) {
        ComPtr<IDWriteLocalizedStrings> family_names;
        if (SUCCEEDED(font_family->GetFamilyNames(family_names.GetAddressOf())) &&
            family_names) {
          const std::string canonical =
              ResolveCanonicalFamilyName(family_names.Get());
          if (IsUserUsableFontFamily(font_family.Get(), canonical)) {
            normalized[i] = canonical;
            continue;
          }
        }
      }
    }

    if (!alias_map_built) {
      alias_to_canonical = BuildAliasLookup(collection.Get());
      alias_map_built = true;
    }
    const auto map_it = alias_to_canonical.find(ToLowerUtf8(trimmed));
    if (map_it != alias_to_canonical.end()) {
      normalized[i] = map_it->second;
    }
  }

  return normalized;
}
