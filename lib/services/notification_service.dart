import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract class NotificationService {
  void startForegroundServiceChannel();
  void notifyNextCaptureScheduled(int delay);
  void notifyRandomCaptureComplete();
  void notifyError(String message);
}

class NotificationServiceImpl implements NotificationService {
  factory NotificationServiceImpl() => _instance;

  NotificationServiceImpl._internal() {
    init();
  }

  static final NotificationServiceImpl _instance =
      NotificationServiceImpl._internal();

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  final AndroidNotificationDetails androidNotificationDetails =
      AndroidNotificationDetails(
    'camera_channel',
    'Camera Capture',
    channelDescription: 'Used for background camera capture',
    importance: Importance.high,
    priority: Priority.high,
    ongoing: true, // Required for Foreground Service
    showWhen: false,
  );
  final AndroidNotificationDetails randomChannelDetails =
      AndroidNotificationDetails(
    'random_camera_channel',
    'Random Camera',
    channelDescription: 'Random Camera Notifications',
    importance: Importance.high,
  );

  void init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await notifications.initialize(initSettings);
  }

  @override
  void startForegroundServiceChannel() async {
    await notifications.show(
      999,
      'Capturing photos in background',
      'Random Camera is running...',
      NotificationDetails(android: androidNotificationDetails),
    );
  }

  @override
  void notifyNextCaptureScheduled(int delay) async {
    await notifications.show(
      DateTime.now()
          .millisecondsSinceEpoch
          .remainder(100000), // Using timestamp for unique ID
      'Next Capture Scheduled',
      'Next photo in $delay seconds',
      NotificationDetails(android: randomChannelDetails),
    );
  }

  @override
  void notifyRandomCaptureComplete() async {
    await notifications.show(
      DateTime.now()
          .millisecondsSinceEpoch
          .remainder(100000), // Using timestamp for unique ID
      'Capture Session Completed',
      'Random capture session has ended',
      NotificationDetails(android: randomChannelDetails),
    );
  }

  @override
  void notifyError(String message) async {
    await notifications.show(
      1002,
      'Capture failed',
      'Error: $message',
      NotificationDetails(android: randomChannelDetails),
    );
  }
}

// TODO remove provider
// final notificationServiceProvider = Provider<NotificationService>((ref) {
//   return NotificationServiceImpl();
// });
