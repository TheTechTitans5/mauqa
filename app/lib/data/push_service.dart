import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/config/env.dart';
import 'repositories/notification_repository.dart';

/// Registers this device for Firebase Cloud Messaging when Firebase is configured at build time.
/// Without configuration the app still works: reminders appear in the in-app Notification Centre.
class PushService {
  PushService(this._repo);
  final NotificationRepository _repo;
  String? _token;
  bool _initialised = false;

  bool get available => Env.pushConfigured && !kIsWeb;

  Future<void> initAndRegister({void Function(RemoteMessage)? onOpen}) async {
    if (!available) return;
    try {
      if (!_initialised) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: Env.firebaseApiKey,
            appId: Env.firebaseAppId,
            messagingSenderId: Env.firebaseSenderId,
            projectId: Env.firebaseProjectId,
          ),
        );
        _initialised = true;
      }
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      _token = await fm.getToken();
      if (_token != null) await _repo.registerDevice(_token!, Platform.isIOS ? 'ios' : 'android');
      fm.onTokenRefresh.listen((t) {
        _token = t;
        _repo.registerDevice(t, Platform.isIOS ? 'ios' : 'android');
      });
      if (onOpen != null) {
        FirebaseMessaging.onMessageOpenedApp.listen(onOpen);
        final initial = await fm.getInitialMessage();
        if (initial != null) onOpen(initial);
      }
    } catch (e) {
      debugPrint('Push registration skipped: $e');
    }
  }

  Future<void> unregister() async {
    if (_token != null) {
      try {
        await _repo.unregisterDevice(_token!);
      } catch (_) {}
    }
  }
}
