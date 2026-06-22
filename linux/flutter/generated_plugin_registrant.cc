//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <ax_layer_shell/ax_layer_shell_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) ax_layer_shell_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AxLayerShellPlugin");
  ax_layer_shell_plugin_register_with_registrar(ax_layer_shell_registrar);
}
