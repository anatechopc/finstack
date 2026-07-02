package triggers_test

import (
	"testing"

	"com.loooans.app/triggers"
)

func TestParseMessagePath(t *testing.T) {
	cases := []struct {
		name      string
		in        string
		room, msg string
		ok        bool
	}{
		{
			name: "dev prefix",
			in:   "projects/p/databases/(default)/documents/dev_chat_rooms/r1/messages/m1",
			room: "r1", msg: "m1", ok: true,
		},
		{
			name: "no prefix (prod)",
			in:   "projects/p/databases/(default)/documents/chat_rooms/r2/messages/m2",
			room: "r2", msg: "m2", ok: true,
		},
		{
			name: "wrong subcollection",
			in:   "projects/p/databases/(default)/documents/dev_chat_rooms/r1/reads/x",
			ok:   false,
		},
		{
			name: "not a message path",
			in:   "projects/p/databases/(default)/documents/dev_users/u1",
			ok:   false,
		},
	}
	for _, c := range cases {
		room, msg, ok := triggers.ParseMessagePath(c.in)
		if ok != c.ok || room != c.room || msg != c.msg {
			t.Errorf("%s: got (%q,%q,%v) want (%q,%q,%v)",
				c.name, room, msg, ok, c.room, c.msg, c.ok)
		}
	}
}
