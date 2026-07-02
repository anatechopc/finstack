/// Pure helpers for identifying and extracting data from chat FCM push payloads.
bool isChatPush(Map<String, dynamic> data) =>
    data['notification_type'] == 'chat';

String? chatRoomId(Map<String, dynamic> data) => data['room_id'] as String?;

int chatSeq(Map<String, dynamic> data) =>
    int.tryParse('${data['seq'] ?? ''}') ?? 0;
