package fakes

import (
	"context"
	"errors"
)

// OtpReader fake — returns a preconfigured OTP entry by token, ErrOtpNotFound,
// or a configured Err if set (for testing transport errors).
type OtpReader struct {
	Entries map[string]map[string]any
	Err     error
}

var ErrOtpNotFound = errors.New("otp not found")

func (r *OtpReader) Read(_ context.Context, token string) (map[string]any, error) {
	if r.Err != nil {
		return nil, r.Err
	}
	if r.Entries == nil {
		return nil, ErrOtpNotFound
	}
	entry, ok := r.Entries[token]
	if !ok {
		return nil, ErrOtpNotFound
	}
	return entry, nil
}

// OtpDeleter fake — records calls.
type OtpDeleter struct {
	DeletedTokens []string
	Err           error
}

func (d *OtpDeleter) Delete(_ context.Context, token string) error {
	d.DeletedTokens = append(d.DeletedTokens, token)
	return d.Err
}

// UserUpdater fake — records calls (uid + fields). Returns Err if set.
type UserUpdate struct {
	UID    string
	Fields map[string]any
}

type UserUpdater struct {
	Updates []UserUpdate
	Err     error
}

func (u *UserUpdater) Update(_ context.Context, uid string, fields map[string]any) error {
	u.Updates = append(u.Updates, UserUpdate{UID: uid, Fields: fields})
	return u.Err
}

// UserReader fake — returns preconfigured Firestore user docs by uid. If
// Err is set it is returned instead. If the uid is not in Users and Err is
// nil, (nil, nil) is returned — the caller (typically a *Core function)
// decides how to map missing-doc into a sentinel error so the fakes stay
// decoupled from any specific package's error variables. ReadCalls records
// every uid argument so tests can assert the email path does not hit
// Firestore.
type UserReader struct {
	Users     map[string]map[string]any
	Err       error
	ReadCalls []string
}

func (r *UserReader) Read(_ context.Context, uid string) (map[string]any, error) {
	r.ReadCalls = append(r.ReadCalls, uid)
	if r.Err != nil {
		return nil, r.Err
	}
	if doc, ok := r.Users[uid]; ok {
		return doc, nil
	}
	return nil, nil
}

// AuthEmailReader fake — returns preconfigured Firebase Auth emails by uid.
// Kept as plain string return (rather than *auth.UserRecord) so this package
// stays free of the firebase.google.com/go dependency. Records every uid
// argument in ReadCalls.
type AuthEmailReader struct {
	Emails    map[string]string
	Err       error
	ReadCalls []string
}

func (r *AuthEmailReader) Read(_ context.Context, uid string) (string, error) {
	r.ReadCalls = append(r.ReadCalls, uid)
	if r.Err != nil {
		return "", r.Err
	}
	return r.Emails[uid], nil
}

// OtpWriter fake — records every RTDB write the Core performs. Tests can
// assert the entry shape (id, userId, otp, expire_at, reason, etc.) and
// that mobile-objective writes include phone/message/sms_status.
type OtpWrite struct {
	Hash  string
	Entry map[string]any
}

type OtpWriter struct {
	Writes []OtpWrite
	Err    error
}

func (w *OtpWriter) Write(_ context.Context, hash string, entry map[string]any) error {
	w.Writes = append(w.Writes, OtpWrite{Hash: hash, Entry: entry})
	return w.Err
}

// EmailSender fake — records every SendEmail call. Tests assert recipients,
// subject, and that the email path never fires for mobile_number objective.
type EmailSend struct {
	Subject    string
	Body       string
	Recipients []string
}

type EmailSender struct {
	Sends []EmailSend
	Err   error
}

func (s *EmailSender) Send(subject, body string, recipients []string) error {
	s.Sends = append(s.Sends, EmailSend{Subject: subject, Body: body, Recipients: recipients})
	return s.Err
}
