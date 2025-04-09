import 'package:camera/camera.dart';
import 'package:flutter_camera_capture_test/main.dart';
import 'package:flutter_camera_capture_test/services/file_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ForegroundCameraService {}

class CameraForegroundService {
  static List<CameraDescription>? _cameras;
  static bool _isServiceRunning = false;

  // Initialize the foreground task
  static Future<void> initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'random_camera_channel',
        channelName: 'Random Camera',
        channelDescription: 'Taking random photos',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // Start the foreground service
  static Future<bool> startForegroundService() async {
    // Initialize cameras if not already done
    if (_cameras == null) {
      try {
        _cameras = await availableCameras();
      } catch (e) {
        print('Error getting cameras: $e');
        return false;
      }
    }

    // Check if we have any cameras
    if (_cameras == null || _cameras!.isEmpty) {
      print('No cameras available');
      return false;
    }

    // Load settings
    final prefs = await SharedPreferences.getInstance();
    final isFrontCamera = prefs.getBool('isFrontCamera') ?? true;

    // Determine which camera to use
    int cameraIndex = isFrontCamera ? 1 : 0;
    if (cameraIndex >= _cameras!.length) {
      cameraIndex = 0;
    }

    // Try to start the foreground service
    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Random Camera Active',
      notificationText: 'Taking photos at random intervals',
      callback: callbackDispatcher,
    );
    _isServiceRunning = result is ServiceRequestSuccess;

    return _isServiceRunning;
  }

  // Stop the foreground service
  static Future<bool> stopForegroundService() async {
    final result = await FlutterForegroundTask.stopService();
    return result is ServiceRequestSuccess;
  }

  // Check if service is running
  static bool isServiceRunning() {
    return _isServiceRunning;
  }
}

class ForegroundCameraServiceImpl extends TaskHandler
    implements ForegroundCameraService {
  int _nextCaptureTime = 0;
  CameraController? _controller;

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Clean up camera resources
    // await _controller?.dispose();
    // _controller = null;
    print("on destroy");
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // Check if it's time to take a photo
    if (DateTime.now().millisecondsSinceEpoch >= _nextCaptureTime) {
      // await _captureImage();
      // _scheduleNextCapture();

      // Send data to main isolate.
      final Map<String, dynamic> data = {
        "timestampMillis": timestamp.millisecondsSinceEpoch,
      };
      FlutterForegroundTask.sendDataToMain(data);
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Initialize camera on start
    // await _initializeCamera();
    _scheduleNextCapture();

    // print('onStart(starter: ${starter.name})');
  }

// Initialize the camera
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Get camera preference from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final isFrontCamera = prefs.getBool('isFrontCamera') ?? true;
      int cameraIndex = isFrontCamera ? 1 : 0;
      if (cameraIndex >= cameras.length) {
        cameraIndex = 0;
      }

      _controller = CameraController(
        cameras[cameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
    } catch (e) {
      print('Error initializing camera in foreground service: $e');
    }
  }

  // Schedule the next capture
  void _scheduleNextCapture() async {
    // Get delay settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final minDelay = prefs.getInt('minDelay') ?? 5;
    final maxDelay = prefs.getInt('maxDelay') ?? 10;

    // Calculate random delay in milliseconds
    final delay = (minDelay +
            (DateTime.now().millisecondsSinceEpoch %
                (maxDelay - minDelay + 1))) *
        1000;
    _nextCaptureTime = DateTime.now().millisecondsSinceEpoch + delay;

    // Update notification with next capture info
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Random Camera Active',
      notificationText: 'Next photo in ${delay ~/ 1000} seconds',
    );
  }

  // Capture an image
  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      await _initializeCamera();
      if (_controller == null || !_controller!.value.isInitialized) {
        return;
      }
    }

    try {
      // Take the picture
      final image = await _controller!.takePicture();

      FileServiceImpl().saveFile(image);

      // Update capture count
      final prefs = await SharedPreferences.getInstance();
      final totalCaptures = (prefs.getInt('totalCaptures') ?? 0) + 1;
      await prefs.setInt('totalCaptures', totalCaptures);

      // Update notification
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Photo Captured',
        notificationText: 'Saved photo #$totalCaptures',
      );
    } catch (e) {
      print('Error capturing image in foreground service: $e');
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Capture Error',
        notificationText:
            'Could not take photo: ${e.toString().substring(0, 30)}...',
      );
    }
  }
}
