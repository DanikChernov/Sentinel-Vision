import 'package:flutter/widgets.dart';

import 'vision_pipeline_controller.dart';

class VisionScope extends InheritedNotifier<VisionPipelineController> {
  const VisionScope({
    required VisionPipelineController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static VisionPipelineController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<VisionScope>();
    assert(scope != null, 'VisionScope is missing from the widget tree.');
    return scope!.notifier!;
  }

  static VisionPipelineController read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<VisionScope>();
    final scope = element?.widget as VisionScope?;
    assert(scope != null, 'VisionScope is missing from the widget tree.');
    return scope!.notifier!;
  }
}
