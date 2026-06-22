import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

// ── Event types ───────────────────────────────────────────────────────────────

sealed class LayerShellEvent {}

class WindowOpenedEvent extends LayerShellEvent {
  WindowOpenedEvent(this.windowId);
  final int windowId;
}

class WindowClosedEvent extends LayerShellEvent {
  WindowClosedEvent(this.windowId);
  final int windowId;
}

class LayerChangedEvent extends LayerShellEvent {
  LayerChangedEvent(this.layer);
  final LayerShellLayer layer;
}

class AnchorsChangedEvent extends LayerShellEvent {
  AnchorsChangedEvent(this.anchors);
  final Set<LayerShellEdge> anchors;
}

class ExclusiveZoneChangedEvent extends LayerShellEvent {
  ExclusiveZoneChangedEvent(this.pixels);
  final int pixels;
}

class KeyboardModeChangedEvent extends LayerShellEvent {
  KeyboardModeChangedEvent(this.mode);
  final LayerShellKeyboardMode mode;
}

class NamespaceChangedEvent extends LayerShellEvent {
  NamespaceChangedEvent(this.namespace);
  final String namespace;
}

class MonitorChangedEvent extends LayerShellEvent {
  MonitorChangedEvent(this.monitor);
  final int monitor;
}

class MarginsChangedEvent extends LayerShellEvent {
  MarginsChangedEvent(
      {required this.left,
      required this.right,
      required this.top,
      required this.bottom});
  final int left, right, top, bottom;
}

class SizeChangedEvent extends LayerShellEvent {
  SizeChangedEvent({required this.width, required this.height});
  final int width, height;
}

class DecoratedChangedEvent extends LayerShellEvent {
  DecoratedChangedEvent(this.decorated);
  final bool decorated;
}

class VisibilityChangedEvent extends LayerShellEvent {
  VisibilityChangedEvent(this.visible);
  final bool visible;
}

// ── Inter-window message ──────────────────────────────────────────────────────

class InterWindowMessage {
  const InterWindowMessage(
      {required this.fromWindowId, required this.payload});
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

  /// Stream of window and layer events for this window's isolate.
  static Stream<LayerShellEvent> get events => _eventsController.stream;

  /// Stream of inter-window messages targeted at this window.
  static Stream<InterWindowMessage> get messages => _messagesController.stream;

  /// Call once before [runApp] in every window (main and sub-windows).
  static void init() {
    _channel.setMethodCallHandler(_handle);
  }

  static Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'onWindowOpened':
        _eventsController
            .add(WindowOpenedEvent((call.arguments as Map)['windowId'] as int));
      case 'onWindowClosed':
        _eventsController
            .add(WindowClosedEvent((call.arguments as Map)['windowId'] as int));
      case 'onMessage':
        final args = call.arguments as Map;
        _messagesController.add(InterWindowMessage(
          fromWindowId: args['fromWindowId'] as int,
          payload: args['payload'] as String,
        ));
      case 'onLayerEvent':
        final event = _parseLayerEvent(call.arguments as Map);
        if (event != null) _eventsController.add(event);
    }
  }

  static LayerShellEvent? _parseLayerEvent(Map args) {
    final type = args['type'] as String?;
    switch (type) {
      case 'layerChanged':
        final name = args['layer'] as String;
        final layer = LayerShellLayer.values.firstWhere(
          (e) => e.name == name,
          orElse: () => LayerShellLayer.top,
        );
        return LayerChangedEvent(layer);

      case 'anchorsChanged':
        final bits = args['anchors'] as int;
        final anchors = LayerShellEdge.values
            .where((e) => (bits & e.bit) != 0)
            .toSet();
        return AnchorsChangedEvent(anchors);

      case 'exclusiveZoneChanged':
        return ExclusiveZoneChangedEvent(args['exclusiveZone'] as int);

      case 'keyboardModeChanged':
        final name = args['mode'] as String;
        final mode = LayerShellKeyboardMode.values.firstWhere(
          (e) => e.name == name,
          orElse: () => LayerShellKeyboardMode.none,
        );
        return KeyboardModeChangedEvent(mode);

      case 'namespaceChanged':
        return NamespaceChangedEvent(args['namespace'] as String);

      case 'monitorChanged':
        return MonitorChangedEvent(args['monitor'] as int);

      case 'marginsChanged':
        return MarginsChangedEvent(
          left: args['left'] as int,
          right: args['right'] as int,
          top: args['top'] as int,
          bottom: args['bottom'] as int,
        );

      case 'sizeChanged':
        return SizeChangedEvent(
          width: args['width'] as int,
          height: args['height'] as int,
        );

      case 'decoratedChanged':
        return DecoratedChangedEvent(args['decorated'] as bool);

      case 'visibilityChanged':
        return VisibilityChangedEvent(args['visible'] as bool);

      default:
        return null;
    }
  }
}

// ── LayerShellMixin ───────────────────────────────────────────────────────────

mixin LayerShellMixin<T extends StatefulWidget> on State<T> {
  final _layerShellSubs = <StreamSubscription<dynamic>>[];

  /// Called when any window is opened (including windows opened by others).
  void onWindowOpened(int windowId) {}

  /// Called when any window is closed.
  void onWindowClosed(int windowId) {}

  /// Called when a message is sent specifically to this window.
  void onMessage(InterWindowMessage message) {}

  /// Called for all layer/visibility events on this window.
  /// Override this for a catch-all, or use the typed sub-overrides below.
  void onLayerShellEvent(LayerShellEvent event) {}

  @override
  void initState() {
    super.initState();
    _layerShellSubs.add(
      AxLayerShellEvents.events.listen((event) {
        if (!mounted) return;
        if (event is WindowOpenedEvent) onWindowOpened(event.windowId);
        if (event is WindowClosedEvent) onWindowClosed(event.windowId);
        onLayerShellEvent(event);
      }),
    );
    _layerShellSubs.add(
      AxLayerShellEvents.messages.listen((msg) {
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
