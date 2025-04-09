import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_camera_capture_test/gallery_screen.dart';
import 'package:flutter_camera_capture_test/services/background_service.dart';
import 'package:flutter_camera_capture_test/services/camera_service.dart';
import 'package:flutter_camera_capture_test/services/file_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
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
      // TODO: (for app release) https://support.google.com/googleplay/android-developer/answer/9214102
      Permission.manageExternalStorage,
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
    // TODO when to need input data
    // final Map<String, dynamic> inputData = {
    //   'isFrontCamera': isFrontCamera,
    //   'started': DateTime.now().millisecondsSinceEpoch,
    // };

    // await Workmanager().registerOneOffTask(
    //   "random_capture_first",
    //   kTaskCaptureRandom,
    //   initialDelay: Duration(seconds: minDelay),
    //   existingWorkPolicy: ExistingWorkPolicy.replace,
    // );

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
      ref.read(cameraServiceProvider).when(
            data: (service) async {
              // Take picture
              final image = await service.captureSingle();

              final file = XFile(image.path);
              await ref.read(fileServiceProvider).saveFile(file);

              // Update stats
              setState(() {
                totalCaptures++;
              });

              await _saveSettings();

              // Show notification
              _showNotification('Photo Captured', 'New photo captured');

              // Schedule next capture
              _scheduleNextCapture();
            },
            error: (error, stackTrace) {
              throw error;
            },
            loading: () {},
          );
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
                  // child: CameraPreview(controller!),
                  child: Text('camera preview'),
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
