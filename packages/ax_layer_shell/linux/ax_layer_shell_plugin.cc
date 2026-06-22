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

  // With a shared engine, all windows use one Dart isolate and therefore one
  // channel. Store it globally so WindowRegistry::broadcast() can reach Dart.
  WindowRegistry::instance().set_event_channel(channel);

  plugin->channel = channel;
  g_object_unref(plugin);
}

void ax_layer_shell_configure_window(GtkWindow* window) {
  gtk_layer_init_for_window(window);
  gtk_window_set_decorated(window, FALSE);

  // Must be set before realize so the compositor allocates an alpha channel.
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);

  // Override GTK's 200×200 default minimum so Flutter's first frame has a
  // sensible viewport width. Without this the engine sees 200×200 at realize
  // time and any Row wider than that overflows before the compositor has sent
  // the real surface dimensions.
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* mon = gdk_display_get_primary_monitor(display);
  if (mon == nullptr) mon = gdk_display_get_monitor(display, 0);
  if (mon != nullptr) {
    GdkRectangle geo;
    gdk_monitor_get_geometry(mon, &geo);
    gtk_widget_set_size_request(GTK_WIDGET(window), geo.width, -1);
  }
}

void ax_layer_shell_set_main_window(GtkWindow* window, FlView* view) {
  WindowRegistry::instance().register_main(window, view);
}
