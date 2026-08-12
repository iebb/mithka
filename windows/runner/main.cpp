#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <iostream>

#include "flutter_window.h"
#include "utils.h"
#include "multi_window_manager/multi_window_manager_plugin.h"

namespace {

constexpr const wchar_t kPrimaryWindowTitle[] = L"mithka";
constexpr const wchar_t kPrimaryInstanceMutex[] =
    L"Local\\ad.neko.mithka.primary-window";

bool ActivateExistingPrimaryWindow() {
  // The mutex is created before Flutter initializes, so a near-simultaneous
  // second launch may briefly precede the first native window.
  for (int attempt = 0; attempt < 50; ++attempt) {
    HWND existing = FindWindowW(Win32Window::GetWindowClassName(),
                                kPrimaryWindowTitle);
    if (existing) {
      DWORD primary_process_id = 0;
      GetWindowThreadProcessId(existing, &primary_process_id);
      if (primary_process_id != 0) {
        AllowSetForegroundWindow(primary_process_id);
      }
      PostMessageW(existing, Win32Window::kActivatePrimaryWindowMessage, 0, 0);
      return true;
    }
    Sleep(100);
  }
  return false;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  HANDLE instance_mutex =
      CreateMutexW(nullptr, FALSE, kPrimaryInstanceMutex);
  if (instance_mutex && GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingPrimaryWindow();
    CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetQuitOnClose(true);
  window.EnableBackgroundTray();
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kPrimaryWindowTitle, origin, size)) {
    if (instance_mutex) {
      CloseHandle(instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }

  MultiWindowManagerPluginSetWindowCreatedCallback(
      [](std::vector<std::string> child_arguments) {
        flutter::DartProject child_project(L"data");
        child_project.set_dart_entrypoint_arguments(std::move(child_arguments));
        auto child = std::make_shared<FlutterWindow>(child_project);
        const Win32Window::Point child_origin(40, 40);
        const Win32Window::Size child_size(880, 520);
        if (!child->Create(L"Mithka Video", child_origin, child_size)) {
          std::cerr << "Failed to create a video window" << std::endl;
        }
        child->SetQuitOnClose(false);
        return child;
      });

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Release Flutter plugins and their COM-backed resources before COM itself.
  window.Destroy();
  ::CoUninitialize();
  if (instance_mutex) {
    CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
