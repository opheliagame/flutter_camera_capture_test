import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_camera_capture_test/home_screen.dart';
import 'package:flutter_camera_capture_test/services/background_service.dart';
import 'package:flutter_camera_capture_test/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Random random = Random();

  Workmanager().executeTask((task, inputData) async {
    print('Background task executed: $task');

    switch (task) {
      case kTaskCaptureOnce:
        // Take a single photo in the background
        BackgroundCameraServiceImpl().captureSingle();

        break;

      case kTaskCaptureRandom:
        // Background capture then schedule next one if session is still active
        BackgroundCameraServiceImpl().captureSingle();

        // Check if we should continue capturing
        final prefs = await SharedPreferences.getInstance();
        final isActive = prefs.getBool('isActive') ?? false;
        final endTime = prefs.getInt('sessionEndTime') ?? 0;

        if (isActive && DateTime.now().millisecondsSinceEpoch < endTime) {
          // Schedule next capture
          final minDelay = prefs.getInt('minDelay') ?? 5;
          final maxDelay = prefs.getInt('maxDelay') ?? 10;
          final nextDelay = minDelay + random.nextInt(maxDelay - minDelay + 1);

          // Schedule next capture
          await Workmanager().registerOneOffTask(
            "random_capture_${DateTime.now().millisecondsSinceEpoch}",
            kTaskCaptureRandom,
            initialDelay: Duration(seconds: nextDelay),
            inputData: inputData,
          );

          NotificationServiceImpl().notifyNextCaptureScheduled(nextDelay);
        } else {
          // Session completed in background
          await prefs.setBool('isActive', false);
          NotificationServiceImpl().notifyRandomCaptureComplete();
        }
        break;

      default:
        break;
    }

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize workmanager for background tasks
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true,
  );

  Workmanager().cancelAll();

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
