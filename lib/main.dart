import 'package:ax_layer_shell/ax_layer_shell.dart';
import 'package:flutter/material.dart';

Future<void> main() => runLayerShell(
  mainConfig: const LayerShellConfig(
    layer: LayerShellLayer.top,
    anchors: {LayerShellEdge.left, LayerShellEdge.right, LayerShellEdge.top},
    height: 45,
    exclusiveZone: 45,
    namespace: 'ax_shell',
  ),
  app: AxShellViewCollection(
    viewBuilder: (context, window) =>
        window.isMain ? const MainApp() : SubWindowApp(window: window),
  ),
);

// ── Main window UI ────────────────────────────────────────────────────────────

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: ValueListenableBuilder(
          valueListenable: AxLayerShell.windows,
          builder: (context, windows, _) {
            final subWindows = windows.where((w) => !w.isMain).toList();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 12),
                const Text(
                  'ax_shell',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _BarButton(
                  label: '+ Bottom Bar',
                  onPressed: () => AxLayerShell.openWindow(
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
                  ),
                ),
                _BarButton(
                  label: '+ Launcher',
                  onPressed: () => AxLayerShell.openWindow(
                    const LayerShellConfig(
                      layer: LayerShellLayer.overlay,
                      keyboardMode: LayerShellKeyboardMode.exclusive,
                      width: 420,
                      height: 520,
                      namespace: 'ax_shell_launcher',
                      dartArguments: 'launcher',
                    ),
                  ),
                ),
                _BarButton(
                  label:
                      'Close Last'
                      '${subWindows.isEmpty ? '' : ' (${subWindows.length})'}',
                  onPressed: subWindows.isEmpty
                      ? null
                      : () => subWindows.last.close(),
                ),
                _BarButton(
                  label: 'Ping All',
                  onPressed: subWindows.isEmpty
                      ? null
                      : () {
                          for (final w in subWindows) {
                            AxLayerShell.sendMessage(
                              w.windowId,
                              'ping from main',
                            );
                          }
                        },
                ),
                const SizedBox(width: 8),
              ],
            );
          },
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

class SubWindowApp extends StatelessWidget {
  const SubWindowApp({super.key, required this.window});

  final LayerShellWindow window;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: switch (window.dartArguments) {
          'bottom_bar' => _BottomBarBody(window: window),
          'launcher' => _LauncherBody(window: window),
          _ => _GenericBody(window: window),
        },
      ),
    );
  }
}

class _BottomBarBody extends StatefulWidget {
  const _BottomBarBody({required this.window});
  final LayerShellWindow window;

  @override
  State<_BottomBarBody> createState() => _BottomBarBodyState();
}

class _BottomBarBodyState extends State<_BottomBarBody>
    with LayerShellMixin<_BottomBarBody> {
  @override
  int get layerShellWindowId => widget.window.windowId;

  final List<String> _messages = [];

  @override
  void onMessage(InterWindowMessage message) {
    setState(() {
      _messages.add('[win ${message.fromWindowId}]: ${message.payload}');
      if (_messages.length > 6) _messages.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 200) return const SizedBox.shrink();
        return Row(
          children: [
            const SizedBox(width: 12),
            Text(
              'Bottom Bar  •  id: ${widget.window.windowId}',
              style: const TextStyle(fontSize: 13),
            ),
            const Spacer(),
            if (_messages.isNotEmpty)
              Text(
                _messages.last,
                style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
              ),
            const SizedBox(width: 12),
            TextButton(
                onPressed: widget.window.close, child: const Text('Close')),
            const SizedBox(width: 8),
          ],
        );
      },
    );
  }
}

class _LauncherBody extends StatefulWidget {
  const _LauncherBody({required this.window});
  final LayerShellWindow window;

  @override
  State<_LauncherBody> createState() => _LauncherBodyState();
}

class _LauncherBodyState extends State<_LauncherBody>
    with LayerShellMixin<_LauncherBody> {
  @override
  int get layerShellWindowId => widget.window.windowId;

  final List<String> _messages = [];

  @override
  void onMessage(InterWindowMessage message) {
    setState(() {
      _messages.add('[win ${message.fromWindowId}]: ${message.payload}');
      if (_messages.length > 6) _messages.removeAt(0);
    });
  }

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
              'Launcher  •  id: ${widget.window.windowId}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            if (_messages.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Messages',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(height: 4),
              ..._messages.map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    m,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: widget.window.close,
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenericBody extends StatelessWidget {
  const _GenericBody({required this.window});
  final LayerShellWindow window;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Window ${window.windowId} — "${window.dartArguments}"',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 14),
          ElevatedButton(onPressed: window.close, child: const Text('Close')),
        ],
      ),
    );
  }
}
