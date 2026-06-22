#ifndef AX_LAYER_SHELL_PLUGIN_H_
#define AX_LAYER_SHELL_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

// Standard Flutter plugin registration entry point.
// Called automatically by generated_plugin_registrant.cc.
FLUTTER_PLUGIN_EXPORT void ax_layer_shell_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

// Called in my_application_activate() BEFORE gtk_widget_realize(window).
// Initialises gtk-layer-shell on the window and disables decorations.
FLUTTER_PLUGIN_EXPORT void ax_layer_shell_configure_window(GtkWindow* window);

// Called in my_application_activate() AFTER fl_register_plugins().
// Registers the main application window as window ID 0 in the plugin registry.
FLUTTER_PLUGIN_EXPORT void ax_layer_shell_set_main_window(GtkWindow* window,
                                                           FlView* view);

G_END_DECLS

#endif  // AX_LAYER_SHELL_PLUGIN_H_
