import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_camera_capture_test/services/camera_service.dart';
import 'package:flutter_camera_capture_test/services/file_service.dart';
import 'package:flutter_camera_capture_test/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define task names
const kTaskCaptureOnce = "capture.once";
const kTaskCaptureRandom = "capture.random";

class BackgroundCameraServiceImpl implements CameraService {
  factory BackgroundCameraServiceImpl() => _instance;

  BackgroundCameraServiceImpl._internal() {
    cameraController = null;

    availableCameras().then((cameras) {
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

        controller.initialize();
        cameraController = controller;
      }
    });
  }

  static final BackgroundCameraServiceImpl _instance =
      BackgroundCameraServiceImpl._internal();

  CameraController? cameraController;

  @override
  Future<XFile> captureSingle() async {
    try {
      // Ensure Flutter binding is initialized (required for background execution)
      WidgetsFlutterBinding.ensureInitialized();

      // Show a persistent notification (required for Foreground Service)
      NotificationServiceImpl().startForegroundServiceChannel();

      // TODO remove
      // await notifications.show(
      //   1000,
      //   'Capturing photo...',
      //   'Random Camera is taking a photo',
      //   const NotificationDetails(android: androidDetails),
      // );

      if (cameraController == null) {
        throw Exception("error capturing image");
      }

      // Determine which camera to use (front or back)
      final prefs = await SharedPreferences.getInstance();

      // Take the picture
      final XFile image = await cameraController!.takePicture();

      FileServiceImpl().saveFile(image);

      // Update capture count
      final totalCaptures = (prefs.getInt('totalCaptures') ?? 0) + 1;
      await prefs.setInt('totalCaptures', totalCaptures);

      // Notify user
      // await notifications.show(
      //   1001,
      //   'Photo captured!',
      //   'New photo saved (Total: $totalCaptures)',
      //   const NotificationDetails(android: androidDetails),
      // );
    } catch (e) {
      print('Error in background capture: $e');
      NotificationServiceImpl().notifyError(e.toString().substring(0, 50));
    }

    final image = await cameraController!.takePicture();
    return image;
  }
}

// TODO remove provider
// final backgroundCameraServiceProvider =
//     FutureProvider<CameraService>((ref) async {
//   final cameras = await availableCameras();

//   if (cameras.isNotEmpty) {
//     // int cameraIndex =
//     //     isFrontCamera ? 1 : 0; // 1 typically front, 0 typically back
//     int cameraIndex = 1;
//     if (cameraIndex >= cameras.length) {
//       cameraIndex = 0;
//     }

//     final controller = CameraController(
//       cameras[cameraIndex],
//       ResolutionPreset.high,
//       enableAudio: false,
//     );

//     await controller.initialize();
//     return BackgroundCameraServiceImpl(controller);
//   }

//   return BackgroundCameraServiceImpl(null);
// });
