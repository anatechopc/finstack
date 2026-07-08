import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:loooans_helpers/loooans_helpers.dart';

/// Throttle window for outgoing typing pings.
const typingThrottle = Duration(seconds: 2);

/// Staleness window: an entry older than this is not "actively typing".
const typingStaleness = Duration(seconds: 5);

/// Pure: may we send another typing ping now?
bool shouldSendTyping({required int? lastSentMillis, required int nowMillis}) {
  if (lastSentMillis == null) return true;
  return nowMillis - lastSentMillis >= typingThrottle.inMilliseconds;
}

/// Pure: is a typing entry stamped [atMillis] still active at [nowMillis]?
bool isActivelyTyping({required int atMillis, required int nowMillis}) {
  return nowMillis - atMillis < typingStaleness.inMilliseconds;
}

/// RTDB-backed typing presence at `typing/{roomId}/{userId}`.
class TypingService {
  TypingService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;
  int? _lastSentMillis;

  String get _prefix {
    if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.staging.name) {
      return 'stg/';
    } else if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.production.name) {
      return '';
    }
    return 'dev/';
  }

  DatabaseReference _ref(String roomId, String userId) =>
      _db.ref('${_prefix}typing/$roomId/$userId');

  /// Write a typing ping (throttled) and clear it on disconnect.
  Future<void> setTyping({
    required String roomId,
    required String userId,
    required int nowMillis,
  }) async {
    if (!shouldSendTyping(
      lastSentMillis: _lastSentMillis,
      nowMillis: nowMillis,
    )) {
      return;
    }
    _lastSentMillis = nowMillis;
    final ref = _ref(roomId, userId);
    await ref.onDisconnect().remove();
    await ref.set(<String, dynamic>{'at': nowMillis});
  }

  /// Explicitly clear this user's typing state.
  Future<void> clearTyping({required String roomId, required String userId}) {
    _lastSentMillis = null;
    return _ref(roomId, userId).remove();
  }

  /// Stream of userIds currently (freshly) typing in [roomId].
  ///
  /// Re-evaluates the [typingStaleness] window on a periodic tick as well as on
  /// each RTDB change, so a lingering entry (e.g. a user who backgrounded without
  /// clearing typing, and no one else types) expires on time instead of staying
  /// shown until the next RTDB event.
  Stream<List<String>> typingStream({
    required String roomId,
    required int Function() clock,
  }) {
    final ref = _db.ref('${_prefix}typing/$roomId');
    late StreamController<List<String>> controller;
    StreamSubscription<DatabaseEvent>? sub;
    Timer? ticker;
    var latest = <String, dynamic>{};
    List<String>? lastEmitted;

    List<String> active() {
      final now = clock();
      return latest.entries
          .where((e) {
            final at = ((e.value as Map)['at'] as num?)?.toInt() ?? 0;
            return isActivelyTyping(atMillis: at, nowMillis: now);
          })
          .map((e) => e.key)
          .toList();
    }

    void push() {
      final next = active();
      if (lastEmitted != null &&
          next.length == lastEmitted!.length &&
          next.every(lastEmitted!.contains)) {
        return; // unchanged — don't spam identical lists
      }
      lastEmitted = next;
      if (!controller.isClosed) controller.add(next);
    }

    controller = StreamController<List<String>>(
      onListen: () {
        sub = ref.onValue.listen((event) {
          final value = event.snapshot.value;
          latest = value == null
              ? <String, dynamic>{}
              : (value as Map).map((k, v) => MapEntry(k as String, v));
          push();
        });
        ticker = Timer.periodic(typingThrottle, (_) => push());
      },
      onCancel: () async {
        await sub?.cancel();
        ticker?.cancel();
      },
    );
    return controller.stream;
  }
}
