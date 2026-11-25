#include "flutter_window.h"

#include <dwrite.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cctype>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

template <typename T>
class ScopedComPtr {
 public:
  ScopedComPtr() = default;
  ~ScopedComPtr() { Reset(); }
  ScopedComPtr(const ScopedComPtr&) = delete;
  ScopedComPtr& operator=(const ScopedComPtr&) = delete;

  T** Put() {
    Reset();
    return &ptr_;
  }
  T* Get() const { return ptr_; }
  T* operator->() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }

  void Reset() {
    if (ptr_) {
      ptr_->Release();
      ptr_ = nullptr;
    }
  }

 private:
  T* ptr_ = nullptr;
};

std::string TrimAsciiWhitespace(const std::string& value) {
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start]))) {
    ++start;
  }
  size_t end = value.size();
  while (end > start &&
         std::isspace(static_cast<unsigned char>(value[end - 1]))) {
    --end;
  }
  return value.substr(start, end - start);
}

flutter::EncodableList ListSystemFonts() {
  ScopedComPtr<IDWriteFactory> factory;
  HRESULT hr = DWriteCreateFactory(
      DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
      reinterpret_cast<IUnknown**>(factory.Put()));
  if (FAILED(hr) || !factory) {
    return {};
  }

  ScopedComPtr<IDWriteFontCollection> collection;
  hr = factory->GetSystemFontCollection(collection.Put(),
                                        /*checkForUpdates=*/TRUE);
  if (FAILED(hr) || !collection) {
    return {};
  }

  const UINT32 family_count = collection->GetFontFamilyCount();
  std::set<std::string> unique_names;
  for (UINT32 i = 0; i < family_count; ++i) {
    ScopedComPtr<IDWriteFontFamily> family;
    if (FAILED(collection->GetFontFamily(i, family.Put())) || !family) {
      continue;
    }

    ScopedComPtr<IDWriteLocalizedStrings> family_names;
    if (FAILED(family->GetFamilyNames(family_names.Put())) || !family_names) {
      continue;
    }

    UINT32 index = 0;
    BOOL exists = FALSE;
    hr = family_names->FindLocaleName(L"en-us", &index, &exists);
    if (FAILED(hr) || !exists) {
      index = 0;
    }

    UINT32 length = 0;
    if (FAILED(family_names->GetStringLength(index, &length)) || length == 0) {
      continue;
    }

    std::wstring wide_name(static_cast<size_t>(length) + 1, L'\0');
    if (FAILED(family_names->GetString(index, wide_name.data(), length + 1))) {
      continue;
    }

    std::string utf8_name =
        TrimAsciiWhitespace(Utf8FromUtf16(wide_name.c_str()));
    if (!utf8_name.empty()) {
      unique_names.insert(std::move(utf8_name));
    }
  }

  std::vector<std::string> sorted(unique_names.begin(), unique_names.end());
  std::sort(sorted.begin(), sorted.end(),
            [](const std::string& a, const std::string& b) {
              const size_t min_len = std::min(a.size(), b.size());
              for (size_t i = 0; i < min_len; ++i) {
                const int ca =
                    std::tolower(static_cast<unsigned char>(a[i]));
                const int cb =
                    std::tolower(static_cast<unsigned char>(b[i]));
                if (ca != cb) return ca < cb;
              }
              if (a.size() != b.size()) return a.size() < b.size();
              return a < b;
            });

  flutter::EncodableList result;
  result.reserve(sorted.size());
  for (const auto& name : sorted) {
    result.emplace_back(name);
  }
  return result;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  // Tear the engine down while virtual dispatch can still reach OnDestroy.
  // Win32Window also guards finalization, so WM_DESTROY cannot clean it twice.
  Destroy();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  fonts_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "mithka/fonts",
          &flutter::StandardMethodCodec::GetInstance());
  fonts_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "listFonts") {
          result->Success(flutter::EncodableValue(ListSystemFonts()));
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (fonts_channel_) {
    fonts_channel_->SetMethodCallHandler(nullptr);
    fonts_channel_ = nullptr;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The primary window must hide before multi_window_manager observes close;
  // that plugin's normal primary close path posts WM_QUIT for the process.
  if (auto tray_result =
          HandleBackgroundTrayMessage(hwnd, message, wparam, lparam)) {
    return *tray_result;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
