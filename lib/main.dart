import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

// Define task names
const kTaskCaptureOnce = "capture.once";
const kTaskCaptureRandom = "capture.random";

// Global variables for background tasks
List<CameraDescription>? _cameras;
CameraController? _backgroundController;
Random _random = Random();

// This is the main callback that will be called by Workmanager in the background
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('Background task executed: $task');

    // Initialize notifications for Foreground Service
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await notifications.initialize(initSettings);

    // Start a Foreground Service (required for Android 9+)
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'camera_channel',
      'Camera Capture',
      channelDescription: 'Used for background camera capture',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true, // Required for Foreground Service
      showWhen: false,
    );
    await notifications.show(
      999,
      'Capturing photos in background',
      'Random Camera is running...',
      const NotificationDetails(android: androidDetails),
    );

    switch (task) {
      case kTaskCaptureOnce:
        // Take a single photo in the background
        await _backgroundCaptureImage(notifications, inputData);
        break;

      case kTaskCaptureRandom:
        // Background capture then schedule next one if session is still active
        await _backgroundCaptureImage(notifications, inputData);

        // Check if we should continue capturing
        final prefs = await SharedPreferences.getInstance();
        final isActive = prefs.getBool('isActive') ?? false;
        final endTime = prefs.getInt('sessionEndTime') ?? 0;

        if (isActive && DateTime.now().millisecondsSinceEpoch < endTime) {
          // Schedule next capture
          final minDelay = prefs.getInt('minDelay') ?? 5;
          final maxDelay = prefs.getInt('maxDelay') ?? 10;
          final nextDelay = minDelay + _random.nextInt(maxDelay - minDelay + 1);

          // Schedule next capture
          await Workmanager().registerOneOffTask(
            "random_capture_${DateTime.now().millisecondsSinceEpoch}",
            kTaskCaptureRandom,
            initialDelay: Duration(seconds: nextDelay),
            inputData: inputData,
          );

          // Show notification
          await _showBackgroundNotification(
            notifications,
            'Next Capture Scheduled',
            'Next photo in $nextDelay seconds',
          );
        } else {
          // Session completed in background
          await prefs.setBool('isActive', false);
          await _showBackgroundNotification(
            notifications,
            'Capture Session Completed',
            'Random capture session has ended',
          );
        }
        break;

      default:
        break;
    }

    return Future.value(true);
  });
}

// Function to capture an image in the background
Future<void> _backgroundCaptureImage(
    FlutterLocalNotificationsPlugin notifications,
    Map<String, dynamic>? inputData) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'camera_channel',
    'Camera Capture',
    channelDescription: 'Used for background camera capture',
    importance: Importance.high,
    priority: Priority.high,
    ongoing: true, // Required for Foreground Service
    showWhen: false,
  );
  try {
    // Ensure Flutter binding is initialized (required for background execution)
    WidgetsFlutterBinding.ensureInitialized();

    // Show a persistent notification (required for Foreground Service)

    await notifications.show(
      1000,
      'Capturing photo...',
      'Random Camera is taking a photo',
      const NotificationDetails(android: androidDetails),
    );

    // Initialize camera if not already initialized
    _cameras ??= await availableCameras();

    if (_cameras != null && _cameras!.isNotEmpty) {
      // Determine which camera to use (front or back)
      final prefs = await SharedPreferences.getInstance();
      final isFrontCamera = prefs.getBool('isFrontCamera') ?? true;
      int cameraIndex = isFrontCamera ? 1 : 0;
      if (cameraIndex >= _cameras!.length) {
        cameraIndex = 0;
      }

      // Initialize camera controller
      _backgroundController?.dispose();
      _backgroundController = CameraController(
        _cameras![cameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      // Initialize and take picture
      await _backgroundController!.initialize();

      // Wait a bit for camera to stabilize
      await Future.delayed(const Duration(milliseconds: 500));

      // Take the picture
      final XFile image = await _backgroundController!.takePicture();

      // Get the save directory
      final directory = await getApplicationDocumentsDirectory();
      final String folder = '${directory.path}/random_captures';
      await Directory(folder).create(recursive: true);

      // Generate filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final String filename = '$folder/capture_$timestamp.jpg';

      // Save image
      final File savedImage = File(filename);
      await savedImage.writeAsBytes(await File(image.path).readAsBytes());

      // Update capture count
      final totalCaptures = (prefs.getInt('totalCaptures') ?? 0) + 1;
      await prefs.setInt('totalCaptures', totalCaptures);

      // Notify user
      await notifications.show(
        1001,
        'Photo captured!',
        'New photo saved (Total: $totalCaptures)',
        const NotificationDetails(android: androidDetails),
      );

      // Clean up
      await _backgroundController!.dispose();
      _backgroundController = null;
    }
  } catch (e) {
    print('Error in background capture: $e');
    await notifications.show(
      1002,
      'Capture failed',
      'Error: ${e.toString().substring(0, 50)}',
      const NotificationDetails(android: androidDetails),
    );
  }
}

// Show notification from background
Future<void> _showBackgroundNotification(
  FlutterLocalNotificationsPlugin notifications,
  String title,
  String message,
) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'random_camera_channel',
    'Random Camera',
    channelDescription: 'Random Camera Notifications',
    importance: Importance.high,
  );

  const NotificationDetails details =
      NotificationDetails(android: androidDetails);

  await notifications.show(
    DateTime.now()
        .millisecondsSinceEpoch
        .remainder(100000), // Using timestamp for unique ID
    title,
    message,
    details,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize workmanager for background tasks
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true,
  );

  Workmanager().cancelAll();

  runApp(const RandomCameraApp());
}

class RandomCameraApp extends StatelessWidget {
  const RandomCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Random Camera',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // Camera variables
  late List<CameraDescription> cameras;
  CameraController? controller;
  bool isInitialized = false;
  bool isFrontCamera = true;

  // Settings
  int minDelay = 5; // seconds
  int maxDelay = 10; // seconds
  int duration = 60; // minutes
  bool isActive = false;

  // Stats
  int totalCaptures = 0;

  // Timer and random generator
  Timer? captureTimer;
  final Random random = Random();

  // Notifications
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Initialize camera
    await _initializeCamera();

    // Request permissions
    await _requestPermissions();

    // Load saved settings
    await _loadSettings();

    // Initialize notifications
    await _initializeNotifications();

    // Check if there was an active session
    await _checkForActiveSession();
  }

  Future<void> _checkForActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final wasActive = prefs.getBool('isActive') ?? false;
    final endTime = prefs.getInt('sessionEndTime') ?? 0;

    // If there was an active session and it hasn't ended
    if (wasActive && DateTime.now().millisecondsSinceEpoch < endTime) {
      setState(() {
        isActive = true;
      });

      // If app is in foreground, start foreground timer
      _scheduleNextCapture();
    } else if (wasActive) {
      // Clear the active flag if session has ended
      await prefs.setBool('isActive', false);
    }
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        int cameraIndex =
            isFrontCamera ? 1 : 0; // 1 typically front, 0 typically back
        if (cameraIndex >= cameras.length) {
          cameraIndex = 0;
        }

        controller = CameraController(
          cameras[cameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
        );

        await controller!.initialize();
        setState(() => isInitialized = true);
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> _requestPermissions() async {
    print("requesting permissions");

    await [
      Permission.camera,
      Permission.storage,
      Permission.notification,
    ].request();

    // Check if permissions are granted
    if (!(await Permission.camera.isGranted)) {
      _showMessage("Camera permission not granted.");
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      minDelay = prefs.getInt('minDelay') ?? 5;
      maxDelay = prefs.getInt('maxDelay') ?? 10;
      duration = prefs.getInt('duration') ?? 60;
      totalCaptures = prefs.getInt('totalCaptures') ?? 0;
      isFrontCamera = prefs.getBool('isFrontCamera') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('minDelay', minDelay);
    await prefs.setInt('maxDelay', maxDelay);
    await prefs.setInt('duration', duration);
    await prefs.setInt('totalCaptures', totalCaptures);
    await prefs.setBool('isFrontCamera', isFrontCamera);
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
    );
  }

  Future<void> _showNotification(String title, String message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'random_camera_channel',
      'Random Camera',
      channelDescription: 'Random Camera Notifications',
      importance: Importance.high,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      message,
      details,
    );
  }

  void _startRandomCapture() async {
    if (!isInitialized || controller == null) {
      _showMessage('Camera not initialized');
      return;
    }

    if (!(await Permission.camera.isGranted)) {
      _showMessage('Permissions required');
      return;
    }

    setState(() {
      isActive = true;
    });

    // Calculate end time and save to preferences
    final endTimeMillis =
        DateTime.now().millisecondsSinceEpoch + (duration * 60 * 1000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isActive', true);
    await prefs.setInt('sessionEndTime', endTimeMillis);
    await _saveSettings();

    _showNotification('Random Camera', 'Started capturing random photos');

    // Schedule first capture in foreground
    _scheduleNextCapture();

    // Register background task for when app is killed
    // This ensures at least one capture happens if app is closed
    final Map<String, dynamic> inputData = {
      'isFrontCamera': isFrontCamera,
      'started': DateTime.now().millisecondsSinceEpoch,
    };

    await Workmanager().registerOneOffTask(
      "random_capture_first",
      kTaskCaptureRandom,
      initialDelay: Duration(seconds: minDelay),
      inputData: inputData,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    // Set end timer
    Timer(Duration(minutes: duration), () {
      _stopRandomCapture();
    });
  }

  void _scheduleNextCapture() {
    if (!isActive) return;

    // Calculate random delay
    final delay = minDelay + random.nextInt(maxDelay - minDelay + 1);

    _showMessage('Next capture in $delay seconds');

    captureTimer?.cancel();
    captureTimer = Timer(Duration(seconds: delay), () {
      _captureImage();
    });
  }

  Future<void> _captureImage() async {
    if (!isInitialized || controller == null || !isActive) return;

    try {
      // Take picture
      final XFile image = await controller!.takePicture();

      // Create directory to save images if not exists
      final directory = await getApplicationDocumentsDirectory();
      final String folder = '${directory.path}/random_captures';
      await Directory(folder).create(recursive: true);

      // Generate filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final String filename = '$folder/capture_$timestamp.jpg';

      // Save image
      final File savedImage = File(filename);
      await savedImage.writeAsBytes(await File(image.path).readAsBytes());

      // Update stats
      setState(() {
        totalCaptures++;
      });

      await _saveSettings();

      // Show notification
      _showNotification('Photo Captured', 'New photo captured');

      // Schedule next capture
      _scheduleNextCapture();
    } catch (e) {
      print('Error capturing image: $e');
      _scheduleNextCapture();
    }
  }

  void _stopRandomCapture() async {
    captureTimer?.cancel();
    setState(() {
      isActive = false;
    });

    // Update preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isActive', false);

    // Cancel any pending background tasks
    await Workmanager().cancelAll();

    _showNotification('Random Camera', 'Stopped capturing photos');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Durations.short1),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    captureTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // App is going to background or being killed
      captureTimer?.cancel();

      // Schedule background task if session is active
      if (isActive) {
        // Get time remaining for the session
        final endTime =
            DateTime.now().millisecondsSinceEpoch + (duration * 60 * 1000);
        final Map<String, dynamic> inputData = {
          'isFrontCamera': isFrontCamera,
          'endTime': endTime,
        };

        // Schedule background task to continue capturing
        Workmanager().registerOneOffTask(
          "random_capture_lifecycle_${DateTime.now().millisecondsSinceEpoch}",
          kTaskCaptureRandom,
          initialDelay: Duration(seconds: minDelay),
          inputData: inputData,
        );
      }
    } else if (state == AppLifecycleState.resumed && isActive) {
      // App returned to foreground
      // Cancel background tasks and resume foreground operation
      Workmanager().cancelAll();
      _scheduleNextCapture();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Random Camera'),
        centerTitle: true,
        actions: [
          // Toggle camera button
          IconButton(
            icon: Icon(isFrontCamera ? Icons.camera_front : Icons.camera_rear),
            onPressed: isActive
                ? null
                : () async {
                    setState(() {
                      isFrontCamera = !isFrontCamera;
                    });
                    await _saveSettings();
                    await _initializeCamera();
                  },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview
              if (isInitialized && controller != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CameraPreview(controller!),
                )
              else
                const AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),

              const SizedBox(height: 20),

              // Session status
              if (isActive)
                Card(
                  color: Colors.green.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(Icons.circle, color: Colors.green, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Capture session active',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Settings
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              // Min delay
              Row(
                children: [
                  const Text('Min Delay:'),
                  Expanded(
                    child: Slider(
                      value: minDelay.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '$minDelay seconds',
                      onChanged: isActive
                          ? null
                          : (value) {
                              setState(() {
                                minDelay = value.round();
                                if (minDelay > maxDelay) {
                                  maxDelay = minDelay;
                                }
                              });
                            },
                    ),
                  ),
                  Text('$minDelay s'),
                ],
              ),

              // Max delay
              Row(
                children: [
                  const Text('Max Delay:'),
                  Expanded(
                    child: Slider(
                      value: maxDelay.toDouble(),
                      min: 10,
                      max: 120,
                      divisions: 11,
                      label: '$maxDelay seconds',
                      onChanged: isActive
                          ? null
                          : (value) {
                              setState(() {
                                maxDelay = value.round();
                                if (maxDelay < minDelay) {
                                  minDelay = maxDelay;
                                }
                              });
                            },
                    ),
                  ),
                  Text('$maxDelay s'),
                ],
              ),

              // Duration
              Row(
                children: [
                  const Text('Duration:'),
                  Expanded(
                    child: Slider(
                      value: duration.toDouble(),
                      min: 10,
                      max: 720,
                      divisions: 71,
                      label: '$duration minutes',
                      onChanged: isActive
                          ? null
                          : (value) {
                              setState(() {
                                duration = value.round();
                              });
                            },
                    ),
                  ),
                  Text('$duration min'),
                ],
              ),

              const SizedBox(height: 20),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: isActive ? null : _startRandomCapture,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: isActive ? _stopRandomCapture : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GalleryPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Stats
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Statistics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('Total captures: $totalCaptures'),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            totalCaptures = 0;
                          });
                          _saveSettings();
                        },
                        icon: const Icon(Icons.delete),
                        label: const Text('Reset Stats'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<FileSystemEntity> _capturedImages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCapturedImages();
  }

  Future<void> _loadCapturedImages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final String folder = '${directory.path}/random_captures';

      // Create directory if not exists
      final dir = Directory(folder);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // List files
      List<FileSystemEntity> files = dir.listSync();
      files.sort((a, b) => b.path.compareTo(a.path)); // Sort by newest

      setState(() {
        _capturedImages = files;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading images: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured Images'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _capturedImages.isEmpty
              ? const Center(child: Text('No images captured yet'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8.0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _capturedImages.length,
                  itemBuilder: (context, index) {
                    final file = _capturedImages[index];

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FullImageView(
                              imagePath: file.path,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(file.path),
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class FullImageView extends StatelessWidget {
  final String imagePath;

  const FullImageView({
    super.key,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    // Extract timestamp from filename
    final filename = imagePath.split('/').last;
    final timestamp = filename.split('_').last.split('.').first;
    final date = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    final formattedDate =
        '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}:${date.second}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured Image'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final file = File(imagePath);
              await file.delete();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Add share functionality
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
              ),
            ),
          ),
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Captured on: $formattedDate',
              style: const TextStyle(
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
