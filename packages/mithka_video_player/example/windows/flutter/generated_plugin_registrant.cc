//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <fc_native_video_thumbnail/fc_native_video_thumbnail_plugin_c_api.h>
#include <fvp/fvp_plugin_c_api.h>
#include <multi_window_manager/multi_window_manager_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FcNativeVideoThumbnailPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FcNativeVideoThumbnailPluginCApi"));
  FvpPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FvpPluginCApi"));
  MultiWindowManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MultiWindowManagerPlugin"));
}
