import '../../models/detection_result.dart';
import '../../models/frame_context.dart';
import '../../models/inference_diagnostics.dart';

abstract class Detector {
  String get backendLabel;

  DetectorDiagnostics get diagnostics =>
      DetectorDiagnostics(backendName: backendLabel);

  Future<void> initialize() async {}

  Future<void> dispose() async {}

  Future<List<DetectionResult>> detect(FrameContext frame);

  Future<DetectorTestResult> runTestInference({FrameContext? frame}) async {
    return const DetectorTestResult(
      success: false,
      message: 'Detector self-test is not implemented for this backend.',
    );
  }
}
