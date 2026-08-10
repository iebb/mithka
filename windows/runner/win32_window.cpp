#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include <cwchar>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kTrayTooltip[] = L"Mithka";
constexpr UINT kTrayCallbackMessage = WM_APP + 0x51;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayShowCommand = 41001;
constexpr UINT kTrayQuitCommand = 41002;
constexpr UINT_PTR kQuitFallbackTimer = 1;
constexpr UINT kQuitFallbackDelayMs = 5000;

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();
  quit_requested_ = false;
  destruction_finalized_ = false;

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  if (!OnCreate()) {
    Destroy();
    return false;
  }

  if (background_tray_enabled_) {
    AddTrayIcon();
  }
  return true;
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      KillTimer(hwnd, kQuitFallbackTimer);
      RemoveTrayIcon();
      window_handle_ = nullptr;
      child_content_ = nullptr;
      FinalizeDestruction();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  if (!destroying_ && window_handle_) {
    destroying_ = true;
    const HWND window = window_handle_;
    if (!DestroyWindow(window)) {
      // DestroyWindow can fail only for an invalid/cross-thread handle. Avoid
      // re-entering OnDestroy; a later native WM_DESTROY remains authoritative.
      destroying_ = false;
      return;
    }
    destroying_ = false;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::EnableBackgroundTray() {
  background_tray_enabled_ = true;
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  if (window_handle_) {
    AddTrayIcon();
  }
}

const wchar_t* Win32Window::GetWindowClassName() {
  return kWindowClassName;
}

std::optional<LRESULT> Win32Window::HandleBackgroundTrayMessage(
    HWND window,
    UINT const message,
    WPARAM const wparam,
    LPARAM const lparam) noexcept {
  if (!background_tray_enabled_) {
    return std::nullopt;
  }

  if (message == kActivatePrimaryWindowMessage) {
    RestoreFromTray();
    return 0;
  }

  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    tray_icon_added_ = false;
    if (!AddTrayIcon() && !IsWindowVisible(window)) {
      // Never strand a background process without a way to reopen it.
      RestoreFromTray();
    }
    return 0;
  }

  if (message == kTrayCallbackMessage) {
    const UINT event = LOWORD(lparam);
    if (event == WM_LBUTTONUP || event == WM_LBUTTONDBLCLK ||
        event == NIN_SELECT || event == NIN_KEYSELECT) {
      RestoreFromTray();
    } else if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
      ShowTrayMenu();
    }
    return 0;
  }

  if (message == WM_COMMAND) {
    switch (LOWORD(wparam)) {
      case kTrayShowCommand:
        RestoreFromTray();
        return 0;
      case kTrayQuitCommand:
        RequestQuit();
        return 0;
    }
  }

  if (message == WM_TIMER && wparam == kQuitFallbackTimer) {
    KillTimer(window, kQuitFallbackTimer);
    Destroy();
    return 0;
  }

  if (message == WM_QUERYENDSESSION) {
    // A tray-enabled app must never prevent Windows logoff or shutdown.
    return TRUE;
  }
  if (message == WM_ENDSESSION && wparam == TRUE) {
    quit_requested_ = true;
    RemoveTrayIcon();
    return std::nullopt;
  }

  if (!quit_requested_ && tray_icon_added_) {
    if (message == WM_CLOSE) {
      HideToTray();
      return 0;
    }
    if (message == WM_SYSCOMMAND) {
      const WPARAM command = wparam & 0xFFF0;
      if (command == SC_CLOSE || command == SC_MINIMIZE) {
        HideToTray();
        return 0;
      }
    }
    if (message == WM_SIZE && wparam == SIZE_MINIMIZED) {
      HideToTray();
      return 0;
    }
  }

  return std::nullopt;
}

bool Win32Window::AddTrayIcon() {
  if (!background_tray_enabled_ || tray_icon_added_ || !window_handle_) {
    return tray_icon_added_;
  }

  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(tray_icon_data_);
  tray_icon_data_.hWnd = window_handle_;
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
#ifdef NIF_SHOWTIP
  tray_icon_data_.uFlags |= NIF_SHOWTIP;
#endif
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon = reinterpret_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_TRAY_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR | LR_SHARED));
  if (!tray_icon_data_.hIcon) {
    tray_icon_data_.hIcon =
        LoadIconW(GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  }
  wcsncpy_s(tray_icon_data_.szTip, _countof(tray_icon_data_.szTip),
            kTrayTooltip, _TRUNCATE);

  tray_icon_added_ =
      Shell_NotifyIconW(NIM_ADD, &tray_icon_data_) == TRUE;
#ifdef NOTIFYICON_VERSION_4
  if (tray_icon_added_) {
    tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_data_);
  }
#endif
  return tray_icon_added_;
}

void Win32Window::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

void Win32Window::HideToTray() {
  if (window_handle_ && tray_icon_added_) {
    ShowWindow(window_handle_, SW_HIDE);
  }
}

void Win32Window::RestoreFromTray() {
  if (!window_handle_) {
    return;
  }
  int show_command = SW_SHOW;
  if (IsIconic(window_handle_)) {
    show_command = SW_RESTORE;
  } else if (IsZoomed(window_handle_)) {
    show_command = SW_SHOWMAXIMIZED;
  }
  ShowWindow(window_handle_, show_command);
  SetForegroundWindow(window_handle_);
}

void Win32Window::ShowTrayMenu() {
  if (!window_handle_) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kTrayShowCommand, L"Show Mithka");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayQuitCommand, L"Quit Mithka");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(window_handle_);
  const UINT command = TrackPopupMenu(
      menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN |
                TPM_RETURNCMD | TPM_NONOTIFY,
      cursor.x, cursor.y, 0, window_handle_, nullptr);
  DestroyMenu(menu);
  PostMessageW(window_handle_, WM_NULL, 0, 0);

  if (command == kTrayShowCommand) {
    RestoreFromTray();
  } else if (command == kTrayQuitCommand) {
    RequestQuit();
  }
}

void Win32Window::RequestQuit() {
  if (quit_requested_ || !window_handle_) {
    return;
  }
  quit_requested_ = true;
  // Let Dart and multi_window_manager perform their normal confirmed close,
  // but do not hang forever if Quit is chosen before Dart installs its handler
  // or if that handler has crashed.
  if (!SetTimer(window_handle_, kQuitFallbackTimer, kQuitFallbackDelayMs,
                nullptr)) {
    Destroy();
    return;
  }
  if (!PostMessageW(window_handle_, WM_CLOSE, 0, 0)) {
    KillTimer(window_handle_, kQuitFallbackTimer);
    Destroy();
  }
}

void Win32Window::FinalizeDestruction() {
  if (destruction_finalized_) {
    return;
  }
  destruction_finalized_ = true;
  OnDestroy();
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
