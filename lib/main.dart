import 'package:flutter/material.dart';
import 'package:flutter_camera_capture_test/home_screen.dart';
import 'package:flutter_camera_capture_test/services/foreground_camera_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  // Initialize the foreground task
  FlutterForegroundTask.setTaskHandler(ForegroundCameraServiceImpl());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize port for communication between TaskHandler and UI.
  FlutterForegroundTask.initCommunicationPort();

  runApp(ProviderScope(child: const RandomCameraApp()));
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
