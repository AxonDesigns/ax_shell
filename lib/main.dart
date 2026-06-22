import 'package:ax_layer_shell/ax_layer_shell.dart';
import 'package:flutter/material.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  AxLayerShell.initFromArgs(args);
  AxLayerShellEvents.init();

  if (AxLayerShell.currentWindowId != 0) {
    // Sub-window: decide what to show based on windowId / dartArguments.
    runApp(SubWindowApp(
      windowId: AxLayerShell.currentWindowId,
      args: AxLayerShell.currentWindowArgs,
    ));
    return;
  }

  // Main window (ID 0): configure layer shell, then start the app.
  final win = AxLayerShell.mainWindow;
  await win.setLayer(LayerShellLayer.top);
  await win.setAnchors(
      {LayerShellEdge.left, LayerShellEdge.right, LayerShellEdge.top});
  await win.setSize(height: 45);
  await win.setExclusiveZone(45);
  await win.setKeyboardMode(LayerShellKeyboardMode.none);
  await win.setNamespace('ax_shell');

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('ax_shell')),
      ),
    );
  }
}

class SubWindowApp extends StatelessWidget {
  const SubWindowApp({super.key, required this.windowId, required this.args});

  final int windowId;
  final String args;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('Sub-window $windowId — $args')),
      ),
    );
  }
}
