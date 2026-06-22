import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'layer_shell_window.dart';
import 'types.dart';

class AxLayerShell {
  AxLayerShell._();

  static const _channel = MethodChannel('ax.layer_shell');

  /// Reactive list of all currently-open windows, including the main window
  /// (ID 0). Use [ValueListenableBuilder] to rebuild when windows open/close.
  static ValueListenable<List<LayerShellWindow>> get windows => windowsNotifier;

  /// Returns the [LayerShellWindow] for the nearest enclosing view, as
  /// injected by [AxShellViewCollection]. Returns null outside a view tree.
  static LayerShellWindow? windowOf(BuildContext context) =>
      LayerShellWindowScope.maybeOf(context);

  /// Flushes pending Wayland requests and blocks until the compositor's
  /// configure event (which carries the real surface dimensions) is received.
  /// Call from [runLayerShell] after all [set*] calls and before [runWidget].
  static Future<void> sync() => _channel.invokeMethod<void>('sync');

  /// Whether the running compositor supports wlr-layer-shell.
  static Future<bool> isSupported() async =>
      await _channel.invokeMethod<bool>('isSupported') ?? false;

  /// Handle for the main application window (always ID 0).
  static LayerShellWindow get mainWindow => const LayerShellWindow(0);

  /// Open a new GTK+Flutter layer-shell window using the shared engine.
  ///
  /// Returns a [LayerShellWindow] whose [LayerShellWindow.dartArguments] and
  /// [LayerShellWindow.windowId] are populated for use in routing.
  static Future<LayerShellWindow> openWindow(LayerShellConfig config) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'openWindow', config.toMap());
    if (result == null) throw Exception('Failed to open layer shell window');
    final windowId = (result['windowId'] as num?)?.toInt() ?? -1;
    final viewId = (result['viewId'] as num?)?.toInt() ?? -1;
    if (windowId < 0) throw Exception('Failed to open layer shell window');
    return LayerShellWindow(windowId,
        viewId: viewId, dartArguments: config.dartArguments);
  }

  /// Send a targeted message to another window.
  static Future<void> sendMessage(
    int targetWindowId,
    String payload, {
    int fromWindowId = 0,
  }) =>
      _channel.invokeMethod<void>('sendMessage', {
        'targetWindowId': targetWindowId,
        'fromWindowId': fromWindowId,
        'payload': payload,
      });

  /// Query the native side for the windowId associated with a Flutter view ID.
  static Future<int> windowIdForView(int viewId) async {
    final result = await _channel
        .invokeMethod<int>('windowIdForView', {'viewId': viewId});
    return result ?? -1;
  }
}
