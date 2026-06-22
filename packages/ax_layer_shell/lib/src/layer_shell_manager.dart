import 'package:flutter/services.dart';
import 'types.dart';
import 'layer_shell_window.dart';

class AxLayerShell {
  AxLayerShell._();

  static const _channel = MethodChannel('ax.layer_shell');

  /// Whether the running compositor supports wlr-layer-shell.
  static Future<bool> isSupported() async =>
      await _channel.invokeMethod<bool>('isSupported') ?? false;

  /// Handle for the main application window (always ID 0).
  static LayerShellWindow get mainWindow => const LayerShellWindow(0);

  /// Open a new GTK+Flutter window configured for layer shell.
  ///
  /// The new window's Dart isolate receives entrypoint arguments:
  ///   args[0] = "multi_window"
  ///   args[1] = window id (as string)
  ///   args[2] = [config.dartArguments]
  ///
  /// Use [currentWindowId] and [currentWindowArgs] in the new window to
  /// decide which UI to render.
  static Future<LayerShellWindow> openWindow(LayerShellConfig config) async {
    final id = await _channel.invokeMethod<int>('openWindow', config.toMap());
    if (id == null || id < 0) throw Exception('Failed to open layer shell window');
    return LayerShellWindow(id);
  }

  /// The window ID this Dart isolate belongs to.
  /// 0 for the main window; a positive integer for sub-windows.
  static int get currentWindowId => _currentWindowId;

  /// The dartArguments string passed to [LayerShellConfig.dartArguments]
  /// when this window was opened. Empty string for the main window.
  static String get currentWindowArgs => _currentWindowArgs;

  // Set once from main() by reading entrypoint arguments.
  static int _currentWindowId = 0;
  static String _currentWindowArgs = '';

  /// Send a targeted message to another window. Only the target window's
  /// [AxLayerShellEvents.messages] stream receives it.
  static Future<void> sendMessage(int targetWindowId, String payload) =>
      _channel.invokeMethod<void>('sendMessage', {
        'targetWindowId': targetWindowId,
        'fromWindowId': currentWindowId,
        'payload': payload,
      });

  /// Call this at the very start of main() to initialise window identity.
  ///
  /// Example:
  /// ```dart
  /// void main(List<String> args) {
  ///   AxLayerShell.initFromArgs(args);
  ///   if (AxLayerShell.currentWindowId != 0) {
  ///     runSubWindow();
  ///   } else {
  ///     runApp(const MainApp());
  ///   }
  /// }
  /// ```
  static void initFromArgs(List<String> args) {
    if (args.length >= 3 && args[0] == 'multi_window') {
      _currentWindowId = int.tryParse(args[1]) ?? 0;
      _currentWindowArgs = args[2];
    }
  }
}
