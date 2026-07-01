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
        lastSentMillis: _lastSentMillis, nowMillis: nowMillis)) {
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
  Stream<List<String>> typingStream({
    required String roomId,
    required int Function() clock,
  }) {
    return _db.ref('${_prefix}typing/$roomId').onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return <String>[];
      final map = (value as Map).map((k, v) => MapEntry(k as String, v));
      final now = clock();
      return map.entries
          .where((e) {
            final at = ((e.value as Map)['at'] as num?)?.toInt() ?? 0;
            return isActivelyTyping(atMillis: at, nowMillis: now);
          })
          .map((e) => e.key)
          .toList();
    });
  }
}
