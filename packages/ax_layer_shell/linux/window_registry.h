#ifndef WINDOW_REGISTRY_H_
#define WINDOW_REGISTRY_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <atomic>
#include <functional>
#include <map>

struct WindowEntry {
  int id;
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* event_channel;  // native→dart; owned (g_object_ref'd)
};

class WindowRegistry {
 public:
  static WindowRegistry& instance();

  // Register the main application window as ID 0.
  void register_main(GtkWindow* window, FlView* view);

  // Set the callback invoked for each new window's plugin registry.
  void set_window_created_callback(
      std::function<void(FlPluginRegistry*)> callback);

  // Called by register_with_registrar to hand the channel to the registry.
  // The registry takes ownership (g_object_ref).
  void set_pending_channel(FlMethodChannel* channel);

  // Create a new GTK+Flutter layer-shell window with the given config.
  // Returns the assigned window ID (>= 1), or -1 on failure.
  int create(const char* layer, int anchors_bits, int exclusive_zone,
             const char* keyboard_mode, const char* ns, int monitor, int width,
             int height, int margin_left, int margin_right, int margin_top,
             int margin_bottom, bool decorated, const char* dart_arguments);

  WindowEntry* get(int id);
  void remove(int id);

  // Invoke a method on every registered window's event channel.
  void broadcast(const char* method, FlValue* args);

 private:
  WindowRegistry() = default;
  WindowRegistry(const WindowRegistry&) = delete;
  WindowRegistry& operator=(const WindowRegistry&) = delete;

  std::map<int, WindowEntry> windows_;
  std::atomic<int> next_id_{1};
  std::function<void(FlPluginRegistry*)> window_created_callback_;
  FlMethodChannel* pending_channel_ = nullptr;
};

#endif  // WINDOW_REGISTRY_H_
