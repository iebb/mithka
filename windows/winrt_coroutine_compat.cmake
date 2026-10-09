# MSVC 14.51 promotes legacy C++/WinRT coroutine deprecation to STL1011.
# Keep the existing C++17 coroutine ABI for the two pinned Windows plugins.
# Remove this guard when those plugins migrate to standard C++20 coroutines.
# https://github.com/microsoft/STL/blob/main/stl/inc/experimental/coroutine
function(mithka_apply_legacy_winrt_coroutine_compat)
  if(MSVC)
    foreach(plugin_target IN ITEMS
        local_auth_windows_plugin
        permission_handler_windows_plugin)
      if(TARGET ${plugin_target})
        target_compile_definitions(${plugin_target} PRIVATE
          _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
      endif()
    endforeach()
  endif()
endfunction()
