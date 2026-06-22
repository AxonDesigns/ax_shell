#include "layer_shell_handler.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdkwayland.h>
#include <gtk-layer-shell/gtk-layer-shell.h>
#include <gtk/gtk.h>
#include <wayland-client.h>

#include <cstring>

#include "window_registry.h"

// ── helpers ──────────────────────────────────────────────────────────────────

static FlMethodResponse* success(FlValue* result = nullptr) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* error(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

static FlValue* get_arg(FlMethodCall* call, const char* key) {
  FlValue* args = fl_method_call_get_args(call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    return nullptr;
  return fl_value_lookup_string(args, key);
}

static int get_int(FlMethodCall* call, const char* key, int fallback = 0) {
  FlValue* v = get_arg(call, key);
  if (v == nullptr) return fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT)
    return static_cast<int>(fl_value_get_int(v));
  return fallback;
}

static int64_t get_int64(FlMethodCall* call, const char* key,
                          int64_t fallback = -1) {
  FlValue* v = get_arg(call, key);
  if (v == nullptr) return fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return fl_value_get_int(v);
  return fallback;
}

static const char* get_string(FlMethodCall* call, const char* key,
                               const char* fallback = "") {
  FlValue* v = get_arg(call, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_STRING)
    return fallback;
  return fl_value_get_string(v);
}

static bool get_bool(FlMethodCall* call, const char* key,
                     bool fallback = false) {
  FlValue* v = get_arg(call, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_BOOL)
    return fallback;
  return fl_value_get_bool(v) == TRUE;
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

// Broadcast a layer event for a specific window.
// With a shared engine/isolate, all Dart code sees this — the windowId field
// lets Dart filter to the relevant window.
static void fire_layer_event(WindowEntry* entry, const char* type,
                              FlValue* event_map) {
  fl_value_set_string_take(event_map, "type", fl_value_new_string(type));
  fl_value_set_string_take(event_map, "windowId",
                            fl_value_new_int(entry->id));
  WindowRegistry::instance().broadcast("onLayerEvent", event_map);
}

// ── dispatch ─────────────────────────────────────────────────────────────────

void layer_shell_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  const char* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  // ── sync ───────────────────────────────────────────────────────────────────
  if (strcmp(method, "sync") == 0) {
    // GLib releases the context lock during dispatch, so nested iteration is
    // safe. Drain pending GTK work (deferred size-request changes from set*
    // calls) so the Wayland set_size request has been sent before we block.
    while (g_main_context_pending(nullptr))
      g_main_context_iteration(nullptr, FALSE);
    // wl_display_roundtrip is the blocking form of wl_display_sync.
    // gdk_display_sync in GTK3 Wayland calls wl_display_sync (non-blocking),
    // so we call roundtrip directly to guarantee we wait for the compositor's
    // configure event (with the real surface dimensions).
    GdkDisplay* gdk_display = gdk_display_get_default();
    if (GDK_IS_WAYLAND_DISPLAY(gdk_display)) {
      wl_display_roundtrip(gdk_wayland_display_get_wl_display(gdk_display));
    }
    response = success();
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── isSupported ────────────────────────────────────────────────────────────
  if (strcmp(method, "isSupported") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(gtk_layer_is_supported() ? TRUE : FALSE);
    response = success(result);
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── openWindow ─────────────────────────────────────────────────────────────
  if (strcmp(method, "openWindow") == 0) {
    int id = WindowRegistry::instance().create(
        get_string(method_call, "layer", "top"),
        get_int(method_call, "anchors"),
        get_int(method_call, "exclusiveZone"),
        get_string(method_call, "keyboardMode", "none"),
        get_string(method_call, "namespace", "ax_layer_shell"),
        get_int(method_call, "monitor"),
        get_int(method_call, "width"),
        get_int(method_call, "height"),
        get_int(method_call, "marginLeft"),
        get_int(method_call, "marginRight"),
        get_int(method_call, "marginTop"),
        get_int(method_call, "marginBottom"),
        get_bool(method_call, "decorated"),
        get_string(method_call, "dartArguments"));
    if (id < 0) {
      response = error("CREATE_FAILED", "Failed to create window");
    } else {
      WindowEntry* entry = WindowRegistry::instance().get(id);
      g_autoptr(FlValue) result = fl_value_new_map();
      fl_value_set_string_take(result, "windowId", fl_value_new_int(id));
      fl_value_set_string_take(result, "viewId",
                                fl_value_new_int(entry ? entry->view_id : -1));
      response = success(result);
    }
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── getViewArgs ────────────────────────────────────────────────────────────
  if (strcmp(method, "getViewArgs") == 0) {
    int64_t view_id = get_int64(method_call, "viewId");
    std::string args = WindowRegistry::instance().get_view_args(view_id);
    g_autoptr(FlValue) result = fl_value_new_string(args.c_str());
    response = success(result);
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── windowIdForView ────────────────────────────────────────────────────────
  if (strcmp(method, "windowIdForView") == 0) {
    int64_t view_id = get_int64(method_call, "viewId");
    int window_id = WindowRegistry::instance().window_id_for_view(view_id);
    g_autoptr(FlValue) result = fl_value_new_int(window_id);
    response = success(result);
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── sendMessage ────────────────────────────────────────────────────────────
  if (strcmp(method, "sendMessage") == 0) {
    int target_id = get_int(method_call, "targetWindowId", -1);
    int from_id = get_int(method_call, "fromWindowId", -1);
    const char* payload = get_string(method_call, "payload");
    // With shared engine all Dart code is in one isolate — broadcast and
    // let Dart filter by targetWindowId.
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "targetWindowId",
                              fl_value_new_int(target_id));
    fl_value_set_string_take(args, "fromWindowId", fl_value_new_int(from_id));
    fl_value_set_string_take(args, "payload", fl_value_new_string(payload));
    WindowRegistry::instance().broadcast("onMessage", args);
    response = success();
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── window-specific methods ────────────────────────────────────────────────
  int window_id = get_int(method_call, "windowId", -1);
  WindowEntry* entry = WindowRegistry::instance().get(window_id);
  if (entry == nullptr) {
    response = error("INVALID_WINDOW", "Window not found");
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  GtkWindow* win = entry->window;
  FlView* view = entry->view;

  if (strcmp(method, "setLayer") == 0) {
    const char* layer_name = get_string(method_call, "layer");
    gtk_layer_set_layer(win, parse_layer(layer_name));
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "layer", fl_value_new_string(layer_name));
    fire_layer_event(entry, "layerChanged", ev);
    response = success();

  } else if (strcmp(method, "setAnchors") == 0) {
    int bits = get_int(method_call, "anchors");
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_LEFT,
                          (bits & (1 << 0)) ? TRUE : FALSE);
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_RIGHT,
                          (bits & (1 << 1)) ? TRUE : FALSE);
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_TOP,
                          (bits & (1 << 2)) ? TRUE : FALSE);
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_BOTTOM,
                          (bits & (1 << 3)) ? TRUE : FALSE);
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "anchors", fl_value_new_int(bits));
    fire_layer_event(entry, "anchorsChanged", ev);
    response = success();

  } else if (strcmp(method, "clearAnchors") == 0) {
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_LEFT, FALSE);
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_RIGHT, FALSE);
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_TOP, FALSE);
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_BOTTOM, FALSE);
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "anchors", fl_value_new_int(0));
    fire_layer_event(entry, "anchorsChanged", ev);
    response = success();

  } else if (strcmp(method, "setExclusiveZone") == 0) {
    int pixels = get_int(method_call, "exclusiveZone");
    gtk_layer_set_exclusive_zone(win, pixels);
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "exclusiveZone", fl_value_new_int(pixels));
    fire_layer_event(entry, "exclusiveZoneChanged", ev);
    response = success();

  } else if (strcmp(method, "setKeyboardMode") == 0) {
    const char* mode_name = get_string(method_call, "mode");
    gtk_layer_set_keyboard_mode(win, parse_keyboard_mode(mode_name));
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "mode", fl_value_new_string(mode_name));
    fire_layer_event(entry, "keyboardModeChanged", ev);
    response = success();

  } else if (strcmp(method, "setNamespace") == 0) {
    const char* ns = get_string(method_call, "namespace");
    gtk_layer_set_namespace(win, ns);
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "namespace", fl_value_new_string(ns));
    fire_layer_event(entry, "namespaceChanged", ev);
    response = success();

  } else if (strcmp(method, "setMonitor") == 0) {
    int idx = get_int(method_call, "monitor");
    GdkMonitor* mon = gdk_display_get_monitor(gdk_display_get_default(), idx);
    if (mon != nullptr) {
      gtk_layer_set_monitor(win, mon);
      g_autoptr(FlValue) ev = fl_value_new_map();
      fl_value_set_string_take(ev, "monitor", fl_value_new_int(idx));
      fire_layer_event(entry, "monitorChanged", ev);
      response = success();
    } else {
      response = error("INVALID_MONITOR", "Monitor index out of range");
    }

  } else if (strcmp(method, "setMargins") == 0) {
    int l = get_int(method_call, "left");
    int r = get_int(method_call, "right");
    int t = get_int(method_call, "top");
    int b = get_int(method_call, "bottom");
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_LEFT, l);
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_RIGHT, r);
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_TOP, t);
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_BOTTOM, b);
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "left", fl_value_new_int(l));
    fl_value_set_string_take(ev, "right", fl_value_new_int(r));
    fl_value_set_string_take(ev, "top", fl_value_new_int(t));
    fl_value_set_string_take(ev, "bottom", fl_value_new_int(b));
    fire_layer_event(entry, "marginsChanged", ev);
    response = success();

  } else if (strcmp(method, "setSize") == 0) {
    int w = get_int(method_call, "width");
    int h = get_int(method_call, "height");
    gtk_widget_set_size_request(GTK_WIDGET(view), w > 0 ? w : -1,
                                h > 0 ? h : -1);
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "width", fl_value_new_int(w));
    fl_value_set_string_take(ev, "height", fl_value_new_int(h));
    fire_layer_event(entry, "sizeChanged", ev);
    response = success();

  } else if (strcmp(method, "setDecorated") == 0) {
    bool decorated = get_bool(method_call, "decorated");
    gtk_window_set_decorated(win, decorated ? TRUE : FALSE);
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "decorated", fl_value_new_bool(decorated));
    fire_layer_event(entry, "decoratedChanged", ev);
    response = success();

  } else if (strcmp(method, "show") == 0) {
    gtk_widget_show_all(GTK_WIDGET(win));
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "visible", fl_value_new_bool(TRUE));
    fire_layer_event(entry, "visibilityChanged", ev);
    response = success();

  } else if (strcmp(method, "hide") == 0) {
    gtk_widget_hide(GTK_WIDGET(win));
    g_autoptr(FlValue) ev = fl_value_new_map();
    fl_value_set_string_take(ev, "visible", fl_value_new_bool(FALSE));
    fire_layer_event(entry, "visibilityChanged", ev);
    response = success();

  } else if (strcmp(method, "close") == 0) {
    if (window_id == 0) {
      gtk_widget_hide(GTK_WIDGET(win));
    } else {
      WindowRegistry::instance().remove(window_id);
      gtk_widget_destroy(GTK_WIDGET(win));
    }
    response = success();

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}
