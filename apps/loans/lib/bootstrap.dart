import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:loooans_helpers/loooans_helpers.dart';

class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}

/// Background FCM handler — runs in a separate isolate.
///
/// v1: no delivered-ack while fully closed; there is no signed-in user context
/// in the background isolate. Delivered state advances when the app is next
/// opened and the foreground listener / ChatBloc runs.
/// Follow-up: persist uid locally to enable ack here.
@pragma('vm:entry-point')
Future<void> chatBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> bootstrap(
  FutureOr<Widget> Function() builder,
  FirebaseOptions options,
) async {
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  final isProd = const String.fromEnvironment('ENVIRONMENT') ==
      Environments.production.name;
  MyLogger.initializeLogger(logLevel: isProd ? Level.INFO : Level.ALL);
  final log = Logger('main');

  await Firebase.initializeApp(options: options);
  await requestPermissions();

  if (!kIsWeb) {
    await setupFlutterNotifications();
    FirebaseMessaging.onBackgroundMessage(chatBackgroundHandler);
  }

  FlutterError.onError = (details) {
    log.severe(details.exceptionAsString(), details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  // Add cross-flavor configuration here

  runApp(await builder());

  log.info('Application started');
}

/// Create a [AndroidNotificationChannel] for heads up notifications
late AndroidNotificationChannel channel;

bool isFlutterLocalNotificationsInitialized = false;

Future<void> setupFlutterNotifications() async {
  if (isFlutterLocalNotificationsInitialized) {
    return;
  }
  channel = const AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.high,
  );

  flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  /// Create an Android Notification Channel.
  ///
  /// We use this channel in the `AndroidManifest.xml` file to override the
  /// default FCM channel to enable heads up notifications.
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  /// Update the iOS foreground notification presentation options to allow
  /// heads up notifications.
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  isFlutterLocalNotificationsInitialized = true;
}

void showFlutterNotification(RemoteMessage message) {
  if (kDebugMode) {
    print(
        'showFlutterNotification: ${message.data}====${message.notification?.title}',);
  }
  final notification = message.notification;
  final android = message.notification?.android;
  if (notification != null && android != null && !kIsWeb) {
    flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          // TODOadd a proper drawable resource to android, for now using
          //      one that already exists in example app.
          icon: 'launch_background',
        ),
      ),
    );
  }
}

/// Initialize the [FlutterLocalNotificationsPlugin] package.
late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

// check for circular implementation error.
Future<void> requestPermissions() async {
  final checkSettings =
      await FirebaseMessaging.instance.getNotificationSettings();

  // overall notification, the user has not authorized the app.
  // TODO: when implementing iOS notification, check for individual permissions from request
  if (checkSettings.authorizationStatus != AuthorizationStatus.authorized) {
    final requestSettings =
        await FirebaseMessaging.instance.requestPermission();

    if (requestSettings.authorizationStatus != AuthorizationStatus.authorized) {
      unawaited(requestPermissions());
    }
  }
}

Future<void> checkPermissions() async {
  await FirebaseMessaging.instance.getNotificationSettings();
}
