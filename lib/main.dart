import 'dart:async';

import 'package:ax_layer_shell/ax_layer_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Single init: all windows live in one Dart isolate (shared engine).
  AxLayerShellEvents.init();

  // Configure main window layer-shell properties from Dart.
  final win = AxLayerShell.mainWindow;
  await win.setLayer(LayerShellLayer.top);
  await win.setAnchors({
    LayerShellEdge.left,
    LayerShellEdge.right,
    LayerShellEdge.top,
  });
  await win.setSize(height: 45);
  await win.setExclusiveZone(45);
  await win.setKeyboardMode(LayerShellKeyboardMode.none);
  await win.setNamespace('ax_shell');

  // runWidget + ViewCollection is required for shared-engine multi-window.
  runWidget(const AxShellRoot());
}

// ── Root widget: manages all Flutter views ────────────────────────────────────

/// Top-level widget that keeps the [ViewCollection] in sync as windows open
/// and close via [AxLayerShell.openWindow].
class AxShellRoot extends StatefulWidget {
  const AxShellRoot({super.key});

  @override
  State<AxShellRoot> createState() => _AxShellRootState();
}

class _AxShellRootState extends State<AxShellRoot> {
  // viewId → windowId for all currently tracked views
  final Map<int, int> _viewToWindow = {};
  // windowId → dartArguments string
  final Map<int, String> _windowArgs = {};

  StreamSubscription<LayerShellEvent>? _eventSub;

  @override
  void initState() {
    super.initState();

    // Map the implicit (main) view to windowId 0.
    final implicit = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (implicit != null) _viewToWindow[implicit.viewId] = 0;

    _eventSub = AxLayerShellEvents.events.listen((event) {
      switch (event) {
        case WindowOpenedEvent():
          // Store mapping immediately; the FlutterView may appear in
          // platformDispatcher.views slightly after this event fires.
          // Schedule an extra rebuild on the next frame as a safety net.
          _viewToWindow[event.viewId] = event.windowId;
          _windowArgs[event.windowId] = event.dartArguments;
          if (mounted) setState(() {});
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        case WindowClosedEvent():
          final viewId = _viewToWindow.entries
              .where((e) => e.value == event.windowId)
              .map((e) => e.key)
              .firstOrNull;
          if (viewId != null) _viewToWindow.remove(viewId);
          _windowArgs.remove(event.windowId);
          if (mounted) setState(() {});
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final views =
        WidgetsBinding.instance.platformDispatcher.views.toList();

    return ViewCollection(
      views: views.map((view) {
        final windowId = _viewToWindow[view.viewId];
        return View(
          key: ValueKey(view.viewId),
          view: view,
          child: windowId != null
              ? _widgetForWindow(windowId)
              : const SizedBox.shrink(),
        );
      }).toList(),
    );
  }

  Widget _widgetForWindow(int windowId) {
    if (windowId == 0) return const MainApp();
    return SubWindowApp(
        windowId: windowId, args: _windowArgs[windowId] ?? '');
  }
}

// ── Main window UI ────────────────────────────────────────────────────────────

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with LayerShellMixin<MainApp> {
  @override
  int get layerShellWindowId => 0;

  final List<LayerShellWindow> _windows = [];

  @override
  void onWindowClosed(int windowId) {
    setState(() => _windows.removeWhere((w) => w.windowId == windowId));
  }

  Future<void> _openBottomBar() async {
    final win = await AxLayerShell.openWindow(
      const LayerShellConfig(
        layer: LayerShellLayer.top,
        anchors: {
          LayerShellEdge.left,
          LayerShellEdge.right,
          LayerShellEdge.bottom,
        },
        exclusiveZone: 45,
        height: 45,
        namespace: 'ax_shell_bottom',
        dartArguments: 'bottom_bar',
      ),
    );
    setState(() => _windows.add(win));
  }

  Future<void> _openLauncher() async {
    final win = await AxLayerShell.openWindow(
      const LayerShellConfig(
        layer: LayerShellLayer.overlay,
        keyboardMode: LayerShellKeyboardMode.exclusive,
        width: 420,
        height: 520,
        namespace: 'ax_shell_launcher',
        dartArguments: 'launcher',
      ),
    );
    setState(() => _windows.add(win));
  }

  Future<void> _closeLast() async {
    if (_windows.isEmpty) return;
    await _windows.last.close();
  }

  Future<void> _pingAll() async {
    for (final w in _windows) {
      await AxLayerShell.sendMessage(w.windowId, 'ping from main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: Scaffold(
        body: SizedBox(
          height: 45,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 12),
              const Text(
                'ax_shell',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _BarButton(label: '+ Bottom Bar', onPressed: _openBottomBar),
              _BarButton(label: '+ Launcher', onPressed: _openLauncher),
              _BarButton(
                label:
                    'Close Last${_windows.isEmpty ? '' : ' (${_windows.length})'}',
                onPressed: _windows.isEmpty ? null : _closeLast,
              ),
              _BarButton(
                label: 'Ping All',
                onPressed: _windows.isEmpty ? null : _pingAll,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 34),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

// ── Sub-window UI ─────────────────────────────────────────────────────────────

class SubWindowApp extends StatefulWidget {
  const SubWindowApp({super.key, required this.windowId, required this.args});

  final int windowId;
  final String args;

  @override
  State<SubWindowApp> createState() => _SubWindowAppState();
}

class _SubWindowAppState extends State<SubWindowApp>
    with LayerShellMixin<SubWindowApp> {
  @override
  int get layerShellWindowId => widget.windowId;

  final List<String> _messages = [];

  @override
  void onMessage(InterWindowMessage message) {
    setState(() {
      _messages.add('[win ${message.fromWindowId}]: ${message.payload}');
      if (_messages.length > 6) _messages.removeAt(0);
    });
  }

  Future<void> _close() => LayerShellWindow(widget.windowId).close();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: Scaffold(body: _body()),
    );
  }

  Widget _body() {
    return switch (widget.args) {
      'bottom_bar' => _BottomBarBody(
          windowId: widget.windowId,
          messages: _messages,
          onClose: _close,
        ),
      'launcher' => _LauncherBody(
          windowId: widget.windowId,
          messages: _messages,
          onClose: _close,
        ),
      _ => _GenericBody(
          windowId: widget.windowId,
          args: widget.args,
          messages: _messages,
          onClose: _close,
        ),
    };
  }
}

class _BottomBarBody extends StatelessWidget {
  const _BottomBarBody({
    required this.windowId,
    required this.messages,
    required this.onClose,
  });

  final int windowId;
  final List<String> messages;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 12),
        Text(
          'Bottom Bar  •  id: $windowId',
          style: const TextStyle(fontSize: 13),
        ),
        const Spacer(),
        if (messages.isNotEmpty)
          Text(
            messages.last,
            style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
          ),
        const SizedBox(width: 12),
        TextButton(onPressed: onClose, child: const Text('Close')),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _LauncherBody extends StatelessWidget {
  const _LauncherBody({
    required this.windowId,
    required this.messages,
    required this.onClose,
  });

  final int windowId;
  final List<String> messages;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Launcher  •  id: $windowId',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            if (messages.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Messages',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(height: 4),
              ...messages.map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    m,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.greenAccent),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onClose, child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}

class _GenericBody extends StatelessWidget {
  const _GenericBody({
    required this.windowId,
    required this.args,
    required this.messages,
    required this.onClose,
  });

  final int windowId;
  final String args;
  final List<String> messages;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Window $windowId — "$args"',
            style: const TextStyle(fontSize: 15),
          ),
          if (messages.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...messages.map(
              (m) => Text(
                m,
                style: const TextStyle(
                    fontSize: 12, color: Colors.greenAccent),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ElevatedButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}
