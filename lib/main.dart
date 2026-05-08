import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'theme/app_theme.dart';
import 'services/vpn_provider.dart';
import 'services/navigation_provider.dart';
import 'services/update_service.dart';
import 'screens/splash_screen.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'checkUpdateTask') {
      await UpdateService.checkUpdateBackground();
    }
    return Future.value(true);
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. Initialize OneSignal (Only on Mobile)
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize("cbe6f557-3319-4865-95ad-ddc17ec866d0");
      OneSignal.Notifications.requestPermission(true);
    } catch (e) {
      debugPrint("OneSignal initialization failed: $e");
    }
  }

  // 0.1 Initialize Window Manager for Desktop
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1100, 750),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'InterGuard',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 1. Request Essential Permissions
  await _requestPermissions();

  // 2. Initialize Local Notifications (Cross-Platform)
  final AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
  
  final DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final LinuxInitializationSettings initializationSettingsLinux = LinuxInitializationSettings(
    defaultActionName: 'Open InterGuard',
  );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
    macOS: initializationSettingsDarwin,
    linux: initializationSettingsLinux,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      if (details.payload == 'update') {
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
      }
    },
  );

  // 3. Initialize Background Service
  if (Platform.isAndroid || Platform.isIOS) {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    // 4. Initialize Workmanager
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      "1",
      "checkUpdateTask",
      frequency: const Duration(hours: 1), // Standard 1 hour for background check
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  // 5. System UI Setup
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } else {
    // On Desktop/Windows allow all orientations (landscape)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A1929),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const InterGuardApp());
}

Future<void> _requestPermissions() async {
  // Request Notifications (Android 13+)
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  // Request Ignore Battery Optimization (Crucial for background reliability)
  if (Platform.isAndroid) {
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }
}

class InterGuardApp extends StatelessWidget {
  const InterGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VpnProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
      ],
      child: MaterialApp(
        title: 'InterGuard',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const SplashScreen(),
      ),
    );
  }
}
