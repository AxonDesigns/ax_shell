#ifndef WINDOW_REGISTRY_H_
#define WINDOW_REGISTRY_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <atomic>
#include <map>
#include <string>

struct WindowEntry {
  int id;
  int64_t view_id;  // Flutter view ID (from fl_view_get_id)
  GtkWindow* window;
  FlView* view;
};

class WindowRegistry {
 public:
  static WindowRegistry& instance();

  // Register the main application window as ID 0.
  // Stores the shared FlEngine for all subsequent sub-window creation.
  void register_main(GtkWindow* window, FlView* view);

  // Called by register_with_registrar to store the single event channel
  // used for all native→dart callbacks (shared engine, one isolate).
  void set_event_channel(FlMethodChannel* channel);

  // Create a new GTK+Flutter layer-shell window using the shared engine.
  // Returns the assigned window ID (>= 1), or -1 on failure.
  int create(const char* layer, int anchors_bits, int exclusive_zone,
             const char* keyboard_mode, const char* ns, int monitor, int width,
             int height, int margin_left, int margin_right, int margin_top,
             int margin_bottom, bool decorated, const char* dart_arguments);

  WindowEntry* get(int id);
  WindowEntry* get_by_view_id(int64_t view_id);
  void remove(int id);

  // Invoke a method on the shared event channel (reaches all Dart code).
  void broadcast(const char* method, FlValue* args);

  // Return the dartArguments string stored for a given Flutter view ID.
  std::string get_view_args(int64_t view_id) const;

  // Return the windowId for a given Flutter view ID (-1 if not found).
  int window_id_for_view(int64_t view_id) const;

 private:
  WindowRegistry() = default;
  WindowRegistry(const WindowRegistry&) = delete;
  WindowRegistry& operator=(const WindowRegistry&) = delete;

  std::map<int, WindowEntry> windows_;
  std::map<int64_t, std::string> view_args_;  // view_id → dartArguments
  std::atomic<int> next_id_{1};
  FlEngine* main_engine_ = nullptr;
  FlMethodChannel* event_channel_ = nullptr;
};

#endif  // WINDOW_REGISTRY_H_
