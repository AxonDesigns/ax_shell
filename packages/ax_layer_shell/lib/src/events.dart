import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

// ── Event base ────────────────────────────────────────────────────────────────

sealed class LayerShellEvent {}

/// Marker for events that belong to a specific window.
/// [LayerShellMixin] uses this to filter events by [LayerShellMixin.layerShellWindowId].
abstract class LayerWindowEvent extends LayerShellEvent {
  int get windowId;
}

// ── Window lifecycle events ───────────────────────────────────────────────────

class WindowOpenedEvent extends LayerShellEvent {
  WindowOpenedEvent(this.windowId, {required this.viewId, required this.dartArguments});
  final int windowId;
  final int viewId;
  final String dartArguments;
}

class WindowClosedEvent extends LayerShellEvent {
  WindowClosedEvent(this.windowId);
  final int windowId;
}

// ── Layer / property change events ───────────────────────────────────────────

class LayerChangedEvent extends LayerWindowEvent {
  LayerChangedEvent(this.windowId, this.layer);
  @override
  final int windowId;
  final LayerShellLayer layer;
}

class AnchorsChangedEvent extends LayerWindowEvent {
  AnchorsChangedEvent(this.windowId, this.anchors);
  @override
  final int windowId;
  final Set<LayerShellEdge> anchors;
}

class ExclusiveZoneChangedEvent extends LayerWindowEvent {
  ExclusiveZoneChangedEvent(this.windowId, this.pixels);
  @override
  final int windowId;
  final int pixels;
}

class KeyboardModeChangedEvent extends LayerWindowEvent {
  KeyboardModeChangedEvent(this.windowId, this.mode);
  @override
  final int windowId;
  final LayerShellKeyboardMode mode;
}

class NamespaceChangedEvent extends LayerWindowEvent {
  NamespaceChangedEvent(this.windowId, this.namespace);
  @override
  final int windowId;
  final String namespace;
}

class MonitorChangedEvent extends LayerWindowEvent {
  MonitorChangedEvent(this.windowId, this.monitor);
  @override
  final int windowId;
  final int monitor;
}

class MarginsChangedEvent extends LayerWindowEvent {
  MarginsChangedEvent(this.windowId,
      {required this.left,
      required this.right,
      required this.top,
      required this.bottom});
  @override
  final int windowId;
  final int left, right, top, bottom;
}

class SizeChangedEvent extends LayerWindowEvent {
  SizeChangedEvent(this.windowId, {required this.width, required this.height});
  @override
  final int windowId;
  final int width, height;
}

class DecoratedChangedEvent extends LayerWindowEvent {
  DecoratedChangedEvent(this.windowId, this.decorated);
  @override
  final int windowId;
  final bool decorated;
}

class VisibilityChangedEvent extends LayerWindowEvent {
  VisibilityChangedEvent(this.windowId, this.visible);
  @override
  final int windowId;
  final bool visible;
}

// ── Inter-window message ──────────────────────────────────────────────────────

class InterWindowMessage {
  const InterWindowMessage({
    required this.targetWindowId,
    required this.fromWindowId,
    required this.payload,
  });
  final int targetWindowId;
  final int fromWindowId;
  final String payload;
}

// ── AxLayerShellEvents ────────────────────────────────────────────────────────

class AxLayerShellEvents {
  AxLayerShellEvents._();

  static const _channel = MethodChannel('ax.layer_shell');

  static final _eventsController =
      StreamController<LayerShellEvent>.broadcast();
  static final _messagesController =
      StreamController<InterWindowMessage>.broadcast();

  /// Stream of window lifecycle and layer-property change events.
  static Stream<LayerShellEvent> get events => _eventsController.stream;

  /// Stream of all inter-window messages (unfiltered).
  /// [LayerShellMixin] filters these by [LayerShellMixin.layerShellWindowId].
  static Stream<InterWindowMessage> get messages => _messagesController.stream;

  /// Call once — before [runWidget] — in the process entry point.
  static void init() {
    _channel.setMethodCallHandler(_handle);
  }

  static Future<dynamic> _handle(MethodCall call) async {
    final args = call.arguments as Map? ?? {};
    switch (call.method) {
      case 'onWindowOpened':
        _eventsController.add(WindowOpenedEvent(
          (args['windowId'] as num).toInt(),
          viewId: (args['viewId'] as num?)?.toInt() ?? -1,
          dartArguments: args['dartArguments'] as String? ?? '',
        ));
      case 'onWindowClosed':
        _eventsController
            .add(WindowClosedEvent((args['windowId'] as num).toInt()));
      case 'onMessage':
        _messagesController.add(InterWindowMessage(
          targetWindowId: (args['targetWindowId'] as num).toInt(),
          fromWindowId: (args['fromWindowId'] as num).toInt(),
          payload: args['payload'] as String? ?? '',
        ));
      case 'onLayerEvent':
        final event = _parseLayerEvent(args);
        if (event != null) _eventsController.add(event);
    }
  }

  static LayerShellEvent? _parseLayerEvent(Map args) {
    final windowId = (args['windowId'] as num?)?.toInt() ?? -1;
    final type = args['type'] as String?;
    switch (type) {
      case 'layerChanged':
        final name = args['layer'] as String;
        final layer = LayerShellLayer.values.firstWhere(
          (e) => e.name == name,
          orElse: () => LayerShellLayer.top,
        );
        return LayerChangedEvent(windowId, layer);

      case 'anchorsChanged':
        final bits = (args['anchors'] as num).toInt();
        final anchors =
            LayerShellEdge.values.where((e) => (bits & e.bit) != 0).toSet();
        return AnchorsChangedEvent(windowId, anchors);

      case 'exclusiveZoneChanged':
        return ExclusiveZoneChangedEvent(
            windowId, (args['exclusiveZone'] as num).toInt());

      case 'keyboardModeChanged':
        final name = args['mode'] as String;
        final mode = LayerShellKeyboardMode.values.firstWhere(
          (e) => e.name == name,
          orElse: () => LayerShellKeyboardMode.none,
        );
        return KeyboardModeChangedEvent(windowId, mode);

      case 'namespaceChanged':
        return NamespaceChangedEvent(windowId, args['namespace'] as String);

      case 'monitorChanged':
        return MonitorChangedEvent(windowId, (args['monitor'] as num).toInt());

      case 'marginsChanged':
        return MarginsChangedEvent(
          windowId,
          left: (args['left'] as num).toInt(),
          right: (args['right'] as num).toInt(),
          top: (args['top'] as num).toInt(),
          bottom: (args['bottom'] as num).toInt(),
        );

      case 'sizeChanged':
        return SizeChangedEvent(
          windowId,
          width: (args['width'] as num).toInt(),
          height: (args['height'] as num).toInt(),
        );

      case 'decoratedChanged':
        return DecoratedChangedEvent(windowId, args['decorated'] as bool);

      case 'visibilityChanged':
        return VisibilityChangedEvent(windowId, args['visible'] as bool);

      default:
        return null;
    }
  }
}

// ── LayerShellMixin ───────────────────────────────────────────────────────────

/// Mix this into any [State] to receive layer-shell events for a specific window.
///
/// Implementors must override [layerShellWindowId] to identify their window:
/// - Main window: return `0`
/// - Sub-window: return the [LayerShellWindow.windowId] passed to your widget
///
/// ```dart
/// class _MyState extends State<MyWidget> with LayerShellMixin<MyWidget> {
///   @override
///   int get layerShellWindowId => 0; // or widget.window.windowId
///
///   @override
///   void onWindowOpened(int id) => print('opened: $id');
///
///   @override
///   void onMessage(InterWindowMessage msg) {
///     // Only called when msg.targetWindowId == layerShellWindowId
///   }
/// }
/// ```
mixin LayerShellMixin<T extends StatefulWidget> on State<T> {
  /// The window ID this State represents. Used for filtering events and messages.
  int get layerShellWindowId;

  final _layerShellSubs = <StreamSubscription<dynamic>>[];

  /// Called when any window is opened (all windows receive this).
  void onWindowOpened(int windowId) {}

  /// Called when any window is closed (all windows receive this).
  void onWindowClosed(int windowId) {}

  /// Called for inter-window messages whose [targetWindowId] matches
  /// [layerShellWindowId]. Other windows' messages are silently dropped.
  void onMessage(InterWindowMessage message) {}

  /// Called for layer/property events that belong to this window
  /// ([LayerWindowEvent.windowId] == [layerShellWindowId]) and for global
  /// lifecycle events ([WindowOpenedEvent], [WindowClosedEvent]).
  void onLayerShellEvent(LayerShellEvent event) {}

  @override
  void initState() {
    super.initState();
    _layerShellSubs.add(
      AxLayerShellEvents.events.listen((event) {
        if (!mounted) return;
        switch (event) {
          case WindowOpenedEvent():
            onWindowOpened(event.windowId);
            onLayerShellEvent(event);
          case WindowClosedEvent():
            onWindowClosed(event.windowId);
            onLayerShellEvent(event);
          case LayerWindowEvent we when we.windowId == layerShellWindowId:
            onLayerShellEvent(event);
          default:
            break;
        }
      }),
    );
    _layerShellSubs.add(
      AxLayerShellEvents.messages
          .where((msg) => msg.targetWindowId == layerShellWindowId)
          .listen((msg) {
        if (!mounted) return;
        onMessage(msg);
      }),
    );
  }

  @override
  void dispose() {
    for (final sub in _layerShellSubs) {
      sub.cancel();
    }
    _layerShellSubs.clear();
    super.dispose();
  }
}
