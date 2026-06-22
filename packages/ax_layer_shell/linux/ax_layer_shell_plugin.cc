#include "include/ax_layer_shell/ax_layer_shell_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk-layer-shell/gtk-layer-shell.h>
#include <gtk/gtk.h>

#include "layer_shell_handler.h"
#include "window_registry.h"

// ── GObject type boilerplate ─────────────────────────────────────────────────

typedef struct _AxLayerShellPlugin AxLayerShellPlugin;
typedef struct _AxLayerShellPluginClass AxLayerShellPluginClass;

struct _AxLayerShellPluginClass {
  GObjectClass parent_class;
};

struct _AxLayerShellPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
};

#define AX_LAYER_SHELL_PLUGIN(obj)                                    \
  G_TYPE_CHECK_INSTANCE_CAST((obj), ax_layer_shell_plugin_get_type(), \
                              AxLayerShellPlugin)

G_DEFINE_TYPE(AxLayerShellPlugin, ax_layer_shell_plugin, G_TYPE_OBJECT)

static void ax_layer_shell_plugin_dispose(GObject* object) {
  AxLayerShellPlugin* self = AX_LAYER_SHELL_PLUGIN(object);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(ax_layer_shell_plugin_parent_class)->dispose(object);
}

static void ax_layer_shell_plugin_class_init(AxLayerShellPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = ax_layer_shell_plugin_dispose;
}

static void ax_layer_shell_plugin_init(AxLayerShellPlugin* self) {}

// ── Public API ───────────────────────────────────────────────────────────────

void ax_layer_shell_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  AxLayerShellPlugin* plugin = AX_LAYER_SHELL_PLUGIN(
      g_object_new(ax_layer_shell_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "ax.layer_shell",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, layer_shell_method_call_cb, g_object_ref(plugin),
      g_object_unref);

  // Store channel so the registry can associate it with the next window entry.
  WindowRegistry::instance().set_pending_channel(channel);

  plugin->channel = channel;
  g_object_unref(plugin);
}

void ax_layer_shell_configure_window(GtkWindow* window) {
  gtk_layer_init_for_window(window);
  gtk_window_set_decorated(window, FALSE);
}

void ax_layer_shell_set_main_window(GtkWindow* window, FlView* view) {
  WindowRegistry::instance().register_main(window, view);
}

void ax_layer_shell_set_window_created_callback(
    void (*callback)(FlPluginRegistry*)) {
  WindowRegistry::instance().set_window_created_callback(callback);
}
