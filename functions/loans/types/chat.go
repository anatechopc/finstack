package types

// ChatParticipant is a room participant reference shared by the trigger core
// and its test fakes. Type is "user" or "company".
type ChatParticipant struct {
	Id   string
	Type string
}
