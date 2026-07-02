package triggers

import "strings"

// ParseMessagePath extracts roomId and messageId from a Firestore document
// resource name of the form
// projects/{p}/databases/{db}/documents/{prefix}chat_rooms/{roomId}/messages/{messageId}.
// It is prefix-agnostic (dev_/stg_/none).
func ParseMessagePath(name string) (roomId, messageId string, ok bool) {
	const marker = "/documents/"
	idx := strings.Index(name, marker)
	if idx < 0 {
		return "", "", false
	}
	segs := strings.Split(name[idx+len(marker):], "/")
	if len(segs) != 4 {
		return "", "", false
	}
	if !strings.HasSuffix(segs[0], "chat_rooms") || segs[2] != "messages" {
		return "", "", false
	}
	return segs[1], segs[3], true
}
