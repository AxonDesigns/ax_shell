#include "window_registry.h"

#include <gtk-layer-shell/gtk-layer-shell.h>

#include <cstring>
#include <string>

WindowRegistry& WindowRegistry::instance() {
  static WindowRegistry registry;
  return registry;
}

void WindowRegistry::set_event_channel(FlMethodChannel* channel) {
  if (event_channel_) g_object_unref(event_channel_);
  event_channel_ =
      channel ? static_cast<FlMethodChannel*>(g_object_ref(channel)) : nullptr;
}

void WindowRegistry::register_main(GtkWindow* window, FlView* view) {
  main_engine_ = fl_view_get_engine(view);
  int64_t view_id = fl_view_get_id(view);
  windows_[0] = WindowEntry{0, view_id, window, view};
  view_args_[view_id] = "";
}

void WindowRegistry::broadcast(const char* method, FlValue* args) {
  if (event_channel_)
    fl_method_channel_invoke_method(event_channel_, method, args, nullptr,
                                    nullptr, nullptr);
}

std::string WindowRegistry::get_view_args(int64_t view_id) const {
  auto it = view_args_.find(view_id);
  return it != view_args_.end() ? it->second : "";
}

int WindowRegistry::window_id_for_view(int64_t view_id) const {
  for (const auto& [id, entry] : windows_) {
    if (entry.view_id == view_id) return id;
  }
  return -1;
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
  if (!main_engine_) return -1;

  int id = next_id_.fetch_add(1);

  GtkWindow* win = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));

  // Enable RGBA visual before realize for transparency.
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(win));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(win), visual);
  gtk_widget_set_app_paintable(GTK_WIDGET(win), TRUE);

  // gtk_layer_init_for_window must be before realize.
  gtk_layer_init_for_window(win);
  gtk_layer_set_layer(win, parse_layer(layer));
  apply_anchors(win, anchors_bits);
  gtk_layer_set_exclusive_zone(win, exclusive_zone);
  gtk_layer_set_keyboard_mode(win, parse_keyboard_mode(keyboard_mode));
  gtk_layer_set_namespace(win, ns);

  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* mon = nullptr;
  if (monitor >= 0) {
    mon = gdk_display_get_monitor(display, monitor);
    if (mon != nullptr) gtk_layer_set_monitor(win, mon);
  }
  if (mon == nullptr) {
    mon = gdk_display_get_primary_monitor(display);
    if (mon == nullptr) mon = gdk_display_get_monitor(display, 0);
  }

  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_LEFT, margin_left);
  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_RIGHT, margin_right);
  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_TOP, margin_top);
  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_BOTTOM, margin_bottom);
  gtk_window_set_decorated(win, decorated ? TRUE : FALSE);

  // Pre-size the window with monitor geometry so that Flutter's first rendered
  // frame uses the correct dimensions instead of GTK's 200×200 default.
  // The compositor will reassign the true size on map; this just avoids the
  // overflow/underflow that happens when Flutter renders before that occurs.
  if (mon != nullptr) {
    GdkRectangle geo;
    gdk_monitor_get_geometry(mon, &geo);
    // Anchored left+right → full-width; anchored top+bottom → full-height.
    int init_w = (anchors_bits & 3) == 3 ? geo.width : (width > 0 ? width : geo.width);
    int init_h = (anchors_bits & 12) == 12 ? geo.height : (height > 0 ? height : geo.height);
    gtk_window_set_default_size(win, init_w, init_h);
  }

  // Create a view that shares the main window's Flutter engine.
  // This avoids EGL context conflicts that occur with separate engines.
  FlView* view = fl_view_new_for_engine(main_engine_);

  if (width > 0 || height > 0) {
    gtk_widget_set_size_request(GTK_WIDGET(view), width > 0 ? width : -1,
                                height > 0 ? height : -1);
  }

  GdkRGBA bg = {0, 0, 0, 0};
  fl_view_set_background_color(view, &bg);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(win), GTK_WIDGET(view));

  // Show window after first Flutter frame is rendered.
  g_signal_connect_swapped(view, "first-frame",
                            G_CALLBACK(sub_window_first_frame_cb), win);

  gtk_widget_realize(GTK_WIDGET(view));

  // With a shared engine, plugins are already registered — skip re-registration.

  // Disconnect the Flutter quit-on-close handler injected by the embedder.
  gulong handler_id = g_signal_handler_find(
      win, G_SIGNAL_MATCH_FUNC, 0, 0, nullptr,
      reinterpret_cast<gpointer>(gtk_widget_destroy), nullptr);
  if (handler_id != 0) g_signal_handler_disconnect(win, handler_id);

  g_signal_connect(win, "delete-event",
                    G_CALLBACK(sub_window_delete_event_cb),
                    GINT_TO_POINTER(id));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  int64_t view_id = fl_view_get_id(view);
  view_args_[view_id] = dart_arguments ? dart_arguments : "";
  windows_[id] = WindowEntry{id, view_id, win, view};

  // Broadcast window-opened event AFTER storing the entry.
  g_autoptr(FlValue) ev = fl_value_new_map();
  fl_value_set_string_take(ev, "windowId", fl_value_new_int(id));
  fl_value_set_string_take(ev, "viewId", fl_value_new_int(view_id));
  fl_value_set_string_take(ev, "dartArguments",
                            fl_value_new_string(dart_arguments ? dart_arguments : ""));
  broadcast("onWindowOpened", ev);

  return id;
}

WindowEntry* WindowRegistry::get(int id) {
  auto it = windows_.find(id);
  return it == windows_.end() ? nullptr : &it->second;
}

WindowEntry* WindowRegistry::get_by_view_id(int64_t view_id) {
  for (auto& [id, entry] : windows_) {
    if (entry.view_id == view_id) return &entry;
  }
  return nullptr;
}

void WindowRegistry::remove(int id) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;

  // Broadcast before erasing so listeners know the window is gone.
  g_autoptr(FlValue) ev = fl_value_new_map();
  fl_value_set_string_take(ev, "windowId", fl_value_new_int(id));
  broadcast("onWindowClosed", ev);

  view_args_.erase(it->second.view_id);
  windows_.erase(it);
}
