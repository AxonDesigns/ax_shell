enum LayerShellLayer { background, bottom, top, overlay }

enum LayerShellEdge {
  left(1 << 0),
  right(1 << 1),
  top(1 << 2),
  bottom(1 << 3);

  const LayerShellEdge(this.bit);
  final int bit;
}

enum LayerShellKeyboardMode { none, exclusive, onDemand }

class LayerShellConfig {
  const LayerShellConfig({
    this.layer = LayerShellLayer.top,
    this.anchors = const {},
    this.exclusiveZone = 0,
    this.keyboardMode = LayerShellKeyboardMode.none,
    this.namespace = 'ax_layer_shell',
    this.monitor = 0,
    this.width = 0,
    this.height = 0,
    this.marginLeft = 0,
    this.marginRight = 0,
    this.marginTop = 0,
    this.marginBottom = 0,
    this.decorated = false,
    this.dartArguments = '',
  });

  final LayerShellLayer layer;
  final Set<LayerShellEdge> anchors;
  final int exclusiveZone;
  final LayerShellKeyboardMode keyboardMode;
  final String namespace;
  final int monitor;
  final int width;
  final int height;
  final int marginLeft;
  final int marginRight;
  final int marginTop;
  final int marginBottom;
  final bool decorated;

  /// Freeform string forwarded to the new window's Dart entrypoint args[2].
  final String dartArguments;

  Map<String, Object> toMap() => {
        'layer': layer.name,
        'anchors': anchors.fold<int>(0, (a, e) => a | e.bit),
        'exclusiveZone': exclusiveZone,
        'keyboardMode': keyboardMode.name,
        'namespace': namespace,
        'monitor': monitor,
        'width': width,
        'height': height,
        'marginLeft': marginLeft,
        'marginRight': marginRight,
        'marginTop': marginTop,
        'marginBottom': marginBottom,
        'decorated': decorated,
        'dartArguments': dartArguments,
      };
}
