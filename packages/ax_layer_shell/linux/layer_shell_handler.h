#ifndef LAYER_SHELL_HANDLER_H_
#define LAYER_SHELL_HANDLER_H_

#include <flutter_linux/flutter_linux.h>

// Dispatches all incoming method calls on the "ax.layer_shell" channel.
void layer_shell_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data);

#endif  // LAYER_SHELL_HANDLER_H_
