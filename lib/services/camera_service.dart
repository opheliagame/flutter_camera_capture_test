import 'package:camera/camera.dart';
import 'package:riverpod/riverpod.dart';

abstract class CameraService {
  Future<XFile> captureSingle();
}

class CameraServiceImpl implements CameraService {
  CameraController? cameraController;

  CameraServiceImpl(this.cameraController);

  @override
  Future<XFile> captureSingle() async {
    if (cameraController == null) {
      throw Exception("error capturing image");
    }

    final image = await cameraController!.takePicture();
    return image;
  }
}

final cameraServiceProvider = FutureProvider<CameraService>((ref) async {
  final cameras = await availableCameras();

  if (cameras.isNotEmpty) {
    // int cameraIndex =
    //     isFrontCamera ? 1 : 0; // 1 typically front, 0 typically back
    int cameraIndex = 1;
    if (cameraIndex >= cameras.length) {
      cameraIndex = 0;
    }

    final controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await controller.initialize();
    return CameraServiceImpl(controller);
  }

  return CameraServiceImpl(null);
});
