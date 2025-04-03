import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize workmanager for background tasks
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  runApp(const RandomCameraApp());
}

// Background task callback
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Take random photo logic will go here for background execution
    print('Background task executed: $task');
    return Future.value(true);
  });
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
  int minDelay = 30; // seconds
  int maxDelay = 300; // seconds
  int duration = 60; // minutes
  bool isActive = false;

  // Face detection
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
    ),
  );

  // Stats
  int totalCaptures = 0;
  int lookingCaptures = 0;
  int notLookingCaptures = 0;

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
          ResolutionPreset.medium,
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
    await Permission.camera.request();
    await Permission.storage.request();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      minDelay = prefs.getInt('minDelay') ?? 30;
      maxDelay = prefs.getInt('maxDelay') ?? 300;
      duration = prefs.getInt('duration') ?? 60;
      totalCaptures = prefs.getInt('totalCaptures') ?? 0;
      lookingCaptures = prefs.getInt('lookingCaptures') ?? 0;
      notLookingCaptures = prefs.getInt('notLookingCaptures') ?? 0;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('minDelay', minDelay);
    await prefs.setInt('maxDelay', maxDelay);
    await prefs.setInt('duration', duration);
    await prefs.setInt('totalCaptures', totalCaptures);
    await prefs.setInt('lookingCaptures', lookingCaptures);
    await prefs.setInt('notLookingCaptures', notLookingCaptures);
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

    if (!(await Permission.camera.isGranted) ||
        !(await Permission.storage.isGranted)) {
      _showMessage('Permissions required');
      return;
    }

    setState(() {
      isActive = true;
    });

    await _saveSettings();
    _showNotification('Random Camera', 'Started capturing random photos');

    _scheduleNextCapture();

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

      // Process image to detect faces
      final inputImage = InputImage.fromFilePath(image.path);
      final List<Face> faces = await faceDetector.processImage(inputImage);

      // Create directory to save images if not exists
      final directory = await getApplicationDocumentsDirectory();
      final String folder = '${directory.path}/random_captures';
      await Directory(folder).create(recursive: true);

      // Generate filename based on face detection
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final bool isLooking = faces.isNotEmpty;
      final String prefix = isLooking ? 'looking' : 'not_looking';
      final String filename = '$folder/${prefix}_$timestamp.jpg';

      // Save image with new filename
      final File savedImage = File(filename);
      await savedImage.writeAsBytes(await File(image.path).readAsBytes());

      // Update stats
      setState(() {
        totalCaptures++;
        if (isLooking) {
          lookingCaptures++;
        } else {
          notLookingCaptures++;
        }
      });

      await _saveSettings();

      // Show notification
      _showNotification(
          'Photo Captured',
          isLooking
              ? 'You were looking at camera'
              : 'You were not looking at camera');

      // Schedule next capture
      _scheduleNextCapture();
    } catch (e) {
      print('Error capturing image: $e');
      _scheduleNextCapture();
    }
  }

  void _stopRandomCapture() {
    captureTimer?.cancel();
    setState(() {
      isActive = false;
    });
    _showNotification('Random Camera', 'Stopped capturing photos');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    captureTimer?.cancel();
    faceDetector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      captureTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Random Camera'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview
              if (isInitialized && controller != null)
                AspectRatio(
                  aspectRatio: controller!.value.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CameraPreview(controller!),
                  ),
                )
              else
                const AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Center(
                    child: CircularProgressIndicator(),
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
                      max: 120,
                      divisions: 23,
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
                      min: 30,
                      max: 600,
                      divisions: 19,
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
                      Text('Looking at camera: $lookingCaptures'),
                      Text('Not looking at camera: $notLookingCaptures'),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            totalCaptures = 0;
                            lookingCaptures = 0;
                            notLookingCaptures = 0;
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
  String? _selectedFilter;

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

      // Filter if needed
      if (_selectedFilter != null) {
        files = files.where((file) {
          return file.path.contains(_selectedFilter!);
        }).toList();
      }

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
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _selectedFilter = value == 'all' ? null : value;
              });
              _loadCapturedImages();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('All Images'),
              ),
              const PopupMenuItem(
                value: 'looking',
                child: Text('Looking at Camera'),
              ),
              const PopupMenuItem(
                value: 'not_looking',
                child: Text('Not Looking at Camera'),
              ),
            ],
          )
        ],
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
                    final isLooking = file.path.contains('looking_');

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FullImageView(
                              imagePath: file.path,
                              isLooking: isLooking,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(file.path),
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black.withOpacity(0.5),
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  isLooking ? 'Looking' : 'Not Looking',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
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
  final bool isLooking;

  const FullImageView({
    super.key,
    required this.imagePath,
    required this.isLooking,
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
        title: Text(isLooking ? 'Looking at Camera' : 'Not Looking at Camera'),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLooking
                      ? 'You were looking at the camera'
                      : 'You were not looking at the camera',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Captured on: $formattedDate',
                  style: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
