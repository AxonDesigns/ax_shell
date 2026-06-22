import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

/// Shared reactive list of all currently-open windows, including the main
/// window (ID 0). Updated by [AxShellViewCollection] as views open/close.
final windowsNotifier = ValueNotifier<List<LayerShellWindow>>([
  const LayerShellWindow(0),
]);

/// InheritedWidget injected by [AxShellViewCollection] for every Flutter view.
/// Use [AxLayerShell.windowOf] to read from context instead of accessing this directly.
class LayerShellWindowScope extends InheritedWidget {
  const LayerShellWindowScope({
    required this.window,
    required super.child,
    super.key,
  });

  final LayerShellWindow window;

  static LayerShellWindow? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayerShellWindowScope>()?.window;

  @override
  bool updateShouldNotify(LayerShellWindowScope old) => window != old.window;
}

class LayerShellWindow {
  const LayerShellWindow(this.windowId, {this.viewId = -1, this.dartArguments = ''});

  final int windowId;

  /// Flutter view ID returned by the native engine. Used internally to route
  /// rendering via [ViewCollection].
  final int viewId;

  /// Freeform string from [LayerShellConfig.dartArguments]. Use this to route
  /// each window to the right UI in your [AxShellViewCollection.viewBuilder].
  final String dartArguments;

  bool get isMain => windowId == 0;

  @override
  bool operator ==(Object other) =>
      other is LayerShellWindow && other.windowId == windowId;

  @override
  int get hashCode => windowId.hashCode;

  static const _channel = MethodChannel('ax.layer_shell');

  Map<String, Object> get _base => {'windowId': windowId};

  Future<void> _call(String method, [Map<String, Object>? extras]) =>
      _channel.invokeMethod<void>(method, {..._base, ...?extras});

  Future<void> setLayer(LayerShellLayer layer) =>
      _call('setLayer', {'layer': layer.name});

  Future<void> setAnchors(Set<LayerShellEdge> edges) =>
      _call('setAnchors', {'anchors': edges.fold<int>(0, (a, e) => a | e.bit)});

  Future<void> clearAnchors() => _call('clearAnchors');

  Future<void> setExclusiveZone(int pixels) =>
      _call('setExclusiveZone', {'exclusiveZone': pixels});

  Future<void> setKeyboardMode(LayerShellKeyboardMode mode) =>
      _call('setKeyboardMode', {'mode': mode.name});

  Future<void> setNamespace(String ns) =>
      _call('setNamespace', {'namespace': ns});

  Future<void> setMonitor(int index) =>
      _call('setMonitor', {'monitor': index});

  Future<void> setMargins({
    int left = 0,
    int right = 0,
    int top = 0,
    int bottom = 0,
  }) =>
      _call('setMargins', {
        'left': left,
        'right': right,
        'top': top,
        'bottom': bottom,
      });

  /// Set the window size. Pass 0 to let the compositor stretch along anchored edges.
  Future<void> setSize({int width = 0, int height = 0}) =>
      _call('setSize', {'width': width, 'height': height});

  Future<void> setDecorated(bool decorated) =>
      _call('setDecorated', {'decorated': decorated});

  Future<void> show() => _call('show');

  Future<void> hide() => _call('hide');

  /// Closes the window. The main window (ID 0) is only hidden, not destroyed.
  Future<void> close() => _call('close');
}
