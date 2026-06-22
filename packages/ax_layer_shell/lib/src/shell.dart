import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'events.dart';
import 'layer_shell_manager.dart';
import 'layer_shell_window.dart';
import 'types.dart';

/// Signature for the per-view widget builder used by [AxShellViewCollection].
typedef LayerShellViewBuilder = Widget Function(
    BuildContext context, LayerShellWindow window);

/// Bootstraps the layer-shell application.
///
/// Replaces the manual boilerplate of [WidgetsFlutterBinding.ensureInitialized],
/// [AxLayerShellEvents.init], per-property `await win.set*()` calls, and
/// [runWidget]. Call this from `main()` instead:
///
/// ```dart
/// Future<void> main() => runLayerShell(
///   mainConfig: const LayerShellConfig(
///     layer: LayerShellLayer.top,
///     anchors: {LayerShellEdge.left, LayerShellEdge.right, LayerShellEdge.top},
///     height: 45, exclusiveZone: 45, namespace: 'my_shell',
///   ),
///   app: AxShellViewCollection(
///     viewBuilder: (ctx, window) =>
///         window.isMain ? const MainApp() : SubApp(window: window),
///   ),
/// );
/// ```
Future<void> runLayerShell({
  required LayerShellConfig mainConfig,
  required Widget app,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  AxLayerShellEvents.init();

  final win = AxLayerShell.mainWindow;
  await win.setLayer(mainConfig.layer);
  if (mainConfig.anchors.isNotEmpty) { await win.setAnchors(mainConfig.anchors); }
  if (mainConfig.width > 0 || mainConfig.height > 0) {
    await win.setSize(width: mainConfig.width, height: mainConfig.height);
  }
  if (mainConfig.exclusiveZone != 0) { await win.setExclusiveZone(mainConfig.exclusiveZone); }
  await win.setKeyboardMode(mainConfig.keyboardMode);
  if (mainConfig.namespace.isNotEmpty) { await win.setNamespace(mainConfig.namespace); }
  if (mainConfig.monitor > 0) { await win.setMonitor(mainConfig.monitor); }
  await AxLayerShell.sync();
  runWidget(app);
}

/// Manages the [ViewCollection] lifecycle and injects a [LayerShellWindowScope]
/// into every view's subtree so descendants can call [AxLayerShell.windowOf].
///
/// Place this at the root of your widget tree (as [runLayerShell]'s `app`).
/// The [viewBuilder] callback receives a [LayerShellWindow] for each open
/// Flutter view — route however you like:
///
/// ```dart
/// AxShellViewCollection(
///   viewBuilder: (context, window) {
///     if (window.isMain) return const TopBar();
///     return switch (window.dartArguments) {
///       'launcher' => const Launcher(),
///       'bottom'   => const BottomBar(),
///       _          => const SizedBox.shrink(),
///     };
///   },
/// )
/// ```
class AxShellViewCollection extends StatefulWidget {
  const AxShellViewCollection({super.key, required this.viewBuilder});

  final LayerShellViewBuilder viewBuilder;

  @override
  State<AxShellViewCollection> createState() => _AxShellViewCollectionState();
}

class _AxShellViewCollectionState extends State<AxShellViewCollection> {
  // viewId → LayerShellWindow
  final Map<int, LayerShellWindow> _views = {};
  late StreamSubscription<LayerShellEvent> _eventSub;

  @override
  void initState() {
    super.initState();

    // Register the implicit (main) view immediately.
    final implicit = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (implicit != null) {
      _views[implicit.viewId] = const LayerShellWindow(0);
    }

    _eventSub = AxLayerShellEvents.events.listen((event) {
      switch (event) {
        case WindowOpenedEvent():
          final w = LayerShellWindow(
            event.windowId,
            viewId: event.viewId,
            dartArguments: event.dartArguments,
          );
          _views[event.viewId] = w;
          windowsNotifier.value = [...windowsNotifier.value, w];
          if (mounted) setState(() {});
          // The FlutterView may appear in platformDispatcher.views one frame
          // after the event fires — schedule a safety-net rebuild.
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });

        case WindowClosedEvent():
          final viewId = _views.entries
              .where((e) => e.value.windowId == event.windowId)
              .map((e) => e.key)
              .firstOrNull;
          if (viewId != null) _views.remove(viewId);
          windowsNotifier.value = windowsNotifier.value
              .where((w) => w.windowId != event.windowId)
              .toList();
          if (mounted) setState(() {});

        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _eventSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final views =
        WidgetsBinding.instance.platformDispatcher.views.toList();

    return ViewCollection(
      views: views.map((view) {
        final window = _views[view.viewId];
        return View(
          key: ValueKey(view.viewId),
          view: view,
          child: window != null
              ? LayerShellWindowScope(
                  window: window,
                  child: widget.viewBuilder(context, window),
                )
              : const SizedBox.shrink(),
        );
      }).toList(),
    );
  }
}
