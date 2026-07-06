import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/dashboard_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _setupFcm() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final messaging = FirebaseMessaging.instance;
  final settings = await messaging.requestPermission();
  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    final token = await messaging.getToken();
    if (token != null) {
      await userSession.saveFCMToken(token);
    }
  }

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'vera_channel',
            'VERA Notifications',
            channelDescription: 'Notifications de validation',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await userSession.checkAuthState();
  await _setupFcm();
  await FirebaseMessaging.instance.setAutoInitEnabled(true);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VERA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          primary: const Color(0xFF4CAF50),
          secondary: const Color(0xFF00BCD4),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late VoidCallback _listener;
  bool _showWelcome = true;

  @override
  void initState() {
    super.initState();
    _listener = () {
      if (mounted) setState(() {});
    };
    userSession.addListener(_listener);
    _checkWelcomeSeen();
  }

  Future<void> _checkWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('welcome_seen') ?? false;
    if (mounted) {
      setState(() {
        _showWelcome = !seen;
      });
    }
  }

  @override
  void dispose() {
    userSession.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (userSession.isLoggedIn) {
      return const DashboardScreen();
    }
    if (_showWelcome) {
      return const WelcomeScreen();
    }
    return const LoginScreen();
  }
}
