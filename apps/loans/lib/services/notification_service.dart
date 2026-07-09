import 'package:chat_repository/chat_repository.dart';
import 'package:company_repository/company_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/model/notification_model.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/bootstrap.dart';
import 'package:loooans/features/chat/chat_push.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:notification_repository/notification_repository.dart';
import 'package:product_repository/product_repository.dart';
import 'package:user_repository/user_repository.dart';

class NotificationService {
  NotificationService._internal();

  static NotificationService? _instance;

  // TODO: once repositories needed for this service are finalized, remove requiring context and require only the repositories needed.
  static material.BuildContext? _context;
  static Logger? _log;

  static NotificationService get instance {
    if (_instance == null || _context == null || _log == null) {
      throw Exception('Please initialize notification service instance');
    }

    return _instance!;
  }

  static void _handleChatTap(RemoteMessage message) {
    if (!isChatPush(message.data)) return;
    final roomId = chatRoomId(message.data);
    if (roomId == null || _context == null) return;
    GoRouter.of(_context!).go(
      Paths.chatRoom.replaceFirst(':roomId', roomId),
    );
  }

  static void initialize(material.BuildContext context) {
    _log = Logger('notification_service.dart');
    _instance = NotificationService._internal();
    _context = context;
    _log!.info('NotificationService initialized');

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      _log!.finest('Do something when app opens');
      _log!.finest(
          'message: ${message?.data}====${message?.notification?.title}',);
      if (message != null) _handleChatTap(message);
    });

    FirebaseMessaging.onMessage.listen(showFlutterNotification);

    // Foreground delivered-ack for chat messages.
    FirebaseMessaging.onMessage.listen((message) async {
      if (!isChatPush(message.data)) return;
      final roomId = chatRoomId(message.data);
      final seq = chatSeq(message.data);
      if (roomId == null || seq == 0) return;
      final repo = _context?.read<ChatRoomRepository>();
      final userId = AuthenticationService.instance.user.id;
      if (repo == null) return;
      await repo.markDelivered(roomId: roomId, userId: userId, seq: seq);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _log!.finest('A new onMessageOpenedApp event was published!');
      _log!.finest('Do something when app opens');
      _handleChatTap(message);
    });

    _instance!.initializeToken();
  }

  void initializeToken() {
    if (!AuthenticationService.instance.isLoggedIn) {
      return;
    }

    FirebaseMessaging.instance
        .getToken(
            vapidKey:
                'BAiiZsKyb4oRV_AQMLKHtUsAYp5DHDB_Iw3hwxKR6111wheYkRIyA0lPnV-QF5iS49BoD2GDeoqQVRZxEV0NmnY',)
        .then((token) {
      // store token on user document
      _log?.finest('token: $token');
      _storeFCMToken(token);
    }).catchError((Object err) {
      // On web, getToken itself awaits notification permission and REJECTS
      // (messaging/permission-blocked) when the user denies. Since the
      // permission prompt no longer blocks startup (bootstrap fires it
      // unawaited after runApp), a logged-in user can reach getToken before
      // answering the prompt — a denial must log, not surface as an
      // unhandled async error. No token is the correct outcome for a denial.
      _log?.warning('getToken failed (notification permission denied?): $err');
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      // store token on user document
      _log?.finest('refreshToken: $token');
      _storeFCMToken(token);
    });
  }

  Future<void> _storeFCMToken(String? token) async {
    if (token == null) {
      return;
    }

    if (AuthenticationService.instance.user.isPlaceholder) {
      return;
    }

    final device = AuthenticationService.instance.device..token = token;

    await _context!.read<UserRepository>().updateDeviceToken(
          userId: AuthenticationService.instance.user.id,
          device: device,
        );
  }

  void startListening({required String forUser}) {
    _context!.read<NotificationRepository>().loadNext(
      statements: [
        QueryStatement(
          field: 'recipient_id',
          isEqualTo: AuthenticationService.instance.user.id,
        ),
      ],
    );
  }

  Stream<List<NotificationModel>> get notificationStream => _context!
          .read<NotificationRepository>()
          .dataStream
          .asyncMap((notifications) async {
        final models = <NotificationModel>[];
        for (final (index, notification) in notifications.indexed) {
          Product? product;
          Company? company;

          if (notification.data?.productId != null) {
            product = await _context!
                .read<ProductRepository>()
                .get(id: notification.data!.productId!);
          }

          if (notification.data?.companyId != null) {
            company = await _context!
                .read<CompanyRepository>()
                .get(id: notification.data!.companyId!);
          }

          models.add(
            NotificationModel(
              notification: notification,
              product: product,
              company: company,
              isFirst: index == 0,
            ),
          );
        }
        return models;
      });

  void onNotificationPressed(NotificationModel model) {
    // do notification action here
    debugPrint('IMPLEMENT onNotificationPressed');
  }
}
