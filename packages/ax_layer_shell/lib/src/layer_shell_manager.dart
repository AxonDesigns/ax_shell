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

  /// Open a new GTK+Flutter layer-shell window using the shared engine.
  ///
  /// Returns a [LayerShellWindow] whose [viewId] identifies the Flutter view
  /// created for this window. The caller's [ViewCollection] uses [viewId] to
  /// route rendering into the correct GTK surface.
  static Future<LayerShellWindow> openWindow(LayerShellConfig config) async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('openWindow', config.toMap());
    if (result == null) throw Exception('Failed to open layer shell window');
    final windowId = (result['windowId'] as num?)?.toInt() ?? -1;
    final viewId = (result['viewId'] as num?)?.toInt() ?? -1;
    if (windowId < 0) throw Exception('Failed to open layer shell window');
    return LayerShellWindow(windowId, viewId: viewId);
  }

  /// Send a targeted message to another window.
  ///
  /// With a shared engine only one Dart isolate runs; the [AxLayerShellEvents]
  /// stream receives the event and [LayerShellMixin] filters by
  /// [LayerShellMixin.layerShellWindowId] so only the target widget reacts.
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
