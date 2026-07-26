//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <fc_native_video_thumbnail/fc_native_video_thumbnail_plugin.h>
#include <fvp/fvp_plugin.h>
#include <multi_window_manager/multi_window_manager_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) fc_native_video_thumbnail_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FcNativeVideoThumbnailPlugin");
  fc_native_video_thumbnail_plugin_register_with_registrar(fc_native_video_thumbnail_registrar);
  g_autoptr(FlPluginRegistrar) fvp_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FvpPlugin");
  fvp_plugin_register_with_registrar(fvp_registrar);
  g_autoptr(FlPluginRegistrar) multi_window_manager_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MultiWindowManagerPlugin");
  multi_window_manager_plugin_register_with_registrar(multi_window_manager_registrar);
}
