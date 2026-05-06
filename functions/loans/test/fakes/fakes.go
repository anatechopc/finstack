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
