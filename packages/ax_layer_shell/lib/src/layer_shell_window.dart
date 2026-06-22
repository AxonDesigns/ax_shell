import 'package:flutter/services.dart';
import 'types.dart';

class LayerShellWindow {
  const LayerShellWindow(this.windowId);

  final int windowId;

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
