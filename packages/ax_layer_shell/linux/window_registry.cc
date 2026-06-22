#include "window_registry.h"

#include <gtk-layer-shell/gtk-layer-shell.h>

#include <cstring>
#include <string>

WindowRegistry& WindowRegistry::instance() {
  static WindowRegistry registry;
  return registry;
}

void WindowRegistry::set_pending_channel(FlMethodChannel* channel) {
  if (pending_channel_) g_object_unref(pending_channel_);
  pending_channel_ =
      channel ? static_cast<FlMethodChannel*>(g_object_ref(channel)) : nullptr;
}

void WindowRegistry::register_main(GtkWindow* window, FlView* view) {
  windows_[0] = WindowEntry{0, window, view, pending_channel_};
  pending_channel_ = nullptr;
}

void WindowRegistry::set_window_created_callback(
    std::function<void(FlPluginRegistry*)> callback) {
  window_created_callback_ = std::move(callback);
}

void WindowRegistry::broadcast(const char* method, FlValue* args) {
  for (auto& [id, entry] : windows_) {
    if (entry.event_channel)
      fl_method_channel_invoke_method(entry.event_channel, method, args,
                                      nullptr, nullptr, nullptr);
  }
}

static GtkLayerShellLayer parse_layer(const char* name) {
  if (strcmp(name, "background") == 0) return GTK_LAYER_SHELL_LAYER_BACKGROUND;
  if (strcmp(name, "bottom") == 0) return GTK_LAYER_SHELL_LAYER_BOTTOM;
  if (strcmp(name, "overlay") == 0) return GTK_LAYER_SHELL_LAYER_OVERLAY;
  return GTK_LAYER_SHELL_LAYER_TOP;
}

static GtkLayerShellKeyboardMode parse_keyboard_mode(const char* name) {
  if (strcmp(name, "exclusive") == 0)
    return GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE;
  if (strcmp(name, "onDemand") == 0)
    return GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND;
  return GTK_LAYER_SHELL_KEYBOARD_MODE_NONE;
}

static void apply_anchors(GtkWindow* win, int bits) {
  gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_LEFT,
                       (bits & (1 << 0)) != 0 ? TRUE : FALSE);
  gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_RIGHT,
                       (bits & (1 << 1)) != 0 ? TRUE : FALSE);
  gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_TOP,
                       (bits & (1 << 2)) != 0 ? TRUE : FALSE);
  gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_BOTTOM,
                       (bits & (1 << 3)) != 0 ? TRUE : FALSE);
}

static void sub_window_first_frame_cb(GtkWindow* window, FlView*) {
  gtk_widget_show_all(GTK_WIDGET(window));
}

static gboolean sub_window_delete_event_cb(GtkWidget*, GdkEvent*,
                                            gpointer id_ptr) {
  int id = GPOINTER_TO_INT(id_ptr);
  WindowRegistry::instance().remove(id);
  return FALSE;
}

int WindowRegistry::create(const char* layer, int anchors_bits,
                            int exclusive_zone, const char* keyboard_mode,
                            const char* ns, int monitor, int width, int height,
                            int margin_left, int margin_right, int margin_top,
                            int margin_bottom, bool decorated,
                            const char* dart_arguments) {
  int id = next_id_.fetch_add(1);

  GtkWindow* win = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));

  gtk_layer_init_for_window(win);
  gtk_layer_set_layer(win, parse_layer(layer));
  apply_anchors(win, anchors_bits);
  gtk_layer_set_exclusive_zone(win, exclusive_zone);
  gtk_layer_set_keyboard_mode(win, parse_keyboard_mode(keyboard_mode));
  gtk_layer_set_namespace(win, ns);

  GdkDisplay* display = gdk_display_get_default();
  if (monitor >= 0) {
    GdkMonitor* mon = gdk_display_get_monitor(display, monitor);
    if (mon != nullptr) gtk_layer_set_monitor(win, mon);
  }

  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_LEFT, margin_left);
  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_RIGHT, margin_right);
  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_TOP, margin_top);
  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_BOTTOM, margin_bottom);

  gtk_window_set_decorated(win, decorated ? TRUE : FALSE);

  std::string id_str = std::to_string(id);
  gchar* argv[] = {
      const_cast<gchar*>("multi_window"),
      const_cast<gchar*>(id_str.c_str()),
      const_cast<gchar*>(dart_arguments),
      nullptr,
  };

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, argv);

  FlView* view = fl_view_new(project);

  if (width > 0 || height > 0) {
    gtk_widget_set_size_request(GTK_WIDGET(view), width > 0 ? width : -1,
                                height > 0 ? height : -1);
  }

  GdkRGBA bg = {0, 0, 0, 0};
  fl_view_set_background_color(view, &bg);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(win), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame",
                            G_CALLBACK(sub_window_first_frame_cb), win);

  gtk_widget_realize(GTK_WIDGET(view));

  // Register plugins on the new engine — this calls register_with_registrar,
  // which sets pending_channel_.
  if (window_created_callback_) {
    window_created_callback_(FL_PLUGIN_REGISTRY(view));
  }

  // Disconnect Flutter's quit-on-close handler.
  gulong handler_id = g_signal_handler_find(
      win, G_SIGNAL_MATCH_FUNC, 0, 0, nullptr,
      reinterpret_cast<gpointer>(gtk_widget_destroy), nullptr);
  if (handler_id != 0) g_signal_handler_disconnect(win, handler_id);

  g_signal_connect(win, "delete-event",
                    G_CALLBACK(sub_window_delete_event_cb),
                    GINT_TO_POINTER(id));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  // Grab the channel registered by window_created_callback_.
  windows_[id] = WindowEntry{id, win, view, pending_channel_};
  pending_channel_ = nullptr;

  // Broadcast to all windows (including the new one) that a window opened.
  g_autoptr(FlValue) ev = fl_value_new_map();
  fl_value_set_string_take(ev, "windowId", fl_value_new_int(id));
  broadcast("onWindowOpened", ev);

  return id;
}

WindowEntry* WindowRegistry::get(int id) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return nullptr;
  return &it->second;
}

void WindowRegistry::remove(int id) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;

  // Broadcast before erasing so all windows get the event.
  g_autoptr(FlValue) ev = fl_value_new_map();
  fl_value_set_string_take(ev, "windowId", fl_value_new_int(id));
  broadcast("onWindowClosed", ev);

  if (it->second.event_channel) g_object_unref(it->second.event_channel);
  windows_.erase(it);
}
