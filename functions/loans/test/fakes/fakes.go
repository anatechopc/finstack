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

// LoanViewNameUpdate records one UpdateUserLoanViewNames invocation.
type LoanViewNameUpdate struct {
	UserId   string
	FullName string
}

// LoanViewNameUpdater fake — records every user_full_name cascade the user
// changes core performs (the user id + the newly composed full name). Returns
// Err if set so tests can assert error propagation.
type LoanViewNameUpdater struct {
	Updates []LoanViewNameUpdate
	Err     error
}

func (u *LoanViewNameUpdater) Update(_ context.Context, userId, fullName string) error {
	u.Updates = append(u.Updates, LoanViewNameUpdate{UserId: userId, FullName: fullName})
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

// Notifier fake — records every notification the Core writes (recipient,
// title, message, and the data map). Returns Err if set so tests can assert
// error propagation.
type Notification struct {
	RecipientId string
	Title       string
	Message     string
	Data        map[string]string
}

type Notifier struct {
	Notifications []Notification
	Err           error
}

func (n *Notifier) Notify(_ context.Context, recipientId, title, message string, data map[string]string) error {
	n.Notifications = append(n.Notifications, Notification{
		RecipientId: recipientId,
		Title:       title,
		Message:     message,
		Data:        data,
	})
	return n.Err
}

// ScheduleLoanResolver fake — maps loan_schedule_id -> loan_id for the
// payment_created loan resolution. An unknown schedule resolves to "" (the
// core treats that as a graceful no-op). Err is returned instead when set.
type ScheduleLoanResolver struct {
	LoanIds map[string]string
	Err     error
	Calls   []string
}

func (r *ScheduleLoanResolver) LoanIdForSchedule(_ context.Context, scheduleId string) (string, error) {
	r.Calls = append(r.Calls, scheduleId)
	if r.Err != nil {
		return "", r.Err
	}
	return r.LoanIds[scheduleId], nil
}

// LoanInfoReader fake — maps loan_id -> (company_id, product_id). Records every
// loanId argument so tests can assert LoanInfo was called with the resolved id.
type LoanInfo struct {
	CompanyId string
	ProductId string
}

type LoanInfoReader struct {
	Loans map[string]LoanInfo
	Err   error
	Calls []string
}

func (r *LoanInfoReader) LoanInfo(_ context.Context, loanId string) (string, string, error) {
	r.Calls = append(r.Calls, loanId)
	if r.Err != nil {
		return "", "", r.Err
	}
	info := r.Loans[loanId]
	return info.CompanyId, info.ProductId, nil
}

// SubmissionFirstPayment fake — maps submission_id -> the id of its
// earliest-created payment, for the de-dup gate. An unknown submission resolves
// to "". Err is returned instead when set.
type SubmissionFirstPayment struct {
	FirstIds map[string]string
	Err      error
	Calls    []string
}

func (r *SubmissionFirstPayment) FirstPaymentIdForSubmission(_ context.Context, submissionId string) (string, error) {
	r.Calls = append(r.Calls, submissionId)
	if r.Err != nil {
		return "", r.Err
	}
	return r.FirstIds[submissionId], nil
}

// CompanyUsersReader fake — maps company_id -> the user ids to notify,
// regardless of roles (tests supply the exact recipient set). Records every
// companyId argument.
type CompanyUsersReader struct {
	Users map[string][]string
	Err   error
	Calls []string
}

func (r *CompanyUsersReader) CompanyUserIds(_ context.Context, companyId string, _ []string) ([]string, error) {
	r.Calls = append(r.Calls, companyId)
	if r.Err != nil {
		return nil, r.Err
	}
	return r.Users[companyId], nil
}

// CompanyNameReader fake — returns preconfigured company display names by
// company id. If Err is set it is returned instead. Records every companyId
// argument in ReadCalls so tests can assert the lookup happened (or didn't).
type CompanyNameReader struct {
	Names     map[string]string
	Err       error
	ReadCalls []string
}

func (r *CompanyNameReader) Read(_ context.Context, companyId string) (string, error) {
	r.ReadCalls = append(r.ReadCalls, companyId)
	if r.Err != nil {
		return "", r.Err
	}
	return r.Names[companyId], nil
}

// AuthorizeCall records one IsAuthorized invocation.
type AuthorizeCall struct {
	ResponderId string
	CompanyId   string
}

// ResponderAuthorizer fake — reports whether a responder may respond. A nil
// Authorized map authorizes everyone (the convenient default for tests that
// don't exercise the gate); a non-nil map gates specific responder ids. Err is
// returned instead when set. Records every call in Calls.
type ResponderAuthorizer struct {
	Authorized map[string]bool
	Err        error
	Calls      []AuthorizeCall
}

func (a *ResponderAuthorizer) IsAuthorized(_ context.Context, responderId, companyId string) (bool, error) {
	a.Calls = append(a.Calls, AuthorizeCall{ResponderId: responderId, CompanyId: companyId})
	if a.Err != nil {
		return false, a.Err
	}
	if a.Authorized == nil {
		return true, nil
	}
	return a.Authorized[responderId], nil
}

// AuthCreate records one auth-account creation request.
type AuthCreate struct {
	Email       string
	Password    string
	DisplayName string
}

// AuthAccountManager fake — records created/deleted auth accounts. Create
// returns NextUID (default "new-uid") unless CreateErr is set; tests set
// CreateErr to the core's email-exists sentinel to exercise the 409 path.
// Delete records the uid and returns DeleteErr.
type AuthAccountManager struct {
	Created   []AuthCreate
	Deleted   []string
	NextUID   string
	CreateErr error
	DeleteErr error
}

func (m *AuthAccountManager) Create(_ context.Context, email, password, displayName string) (string, error) {
	m.Created = append(m.Created, AuthCreate{Email: email, Password: password, DisplayName: displayName})
	if m.CreateErr != nil {
		return "", m.CreateErr
	}
	uid := m.NextUID
	if uid == "" {
		uid = "new-uid"
	}
	return uid, nil
}

func (m *AuthAccountManager) Delete(_ context.Context, uid string) error {
	m.Deleted = append(m.Deleted, uid)
	return m.DeleteErr
}

// UserAddressWrite records one atomic user+address write.
type UserAddressWrite struct {
	UID     string
	User    map[string]any
	Address map[string]any
}

// UserAddressWriter fake — records every write. Err is returned to exercise the
// compensating-delete path.
type UserAddressWriter struct {
	Writes []UserAddressWrite
	Err    error
}

func (w *UserAddressWriter) Write(_ context.Context, uid string, user, address map[string]any) error {
	w.Writes = append(w.Writes, UserAddressWrite{UID: uid, User: user, Address: address})
	return w.Err
}

// CompanyManagementReader fake — maps companyId -> management_type
// ("app"/"selfManaged"). Unknown company resolves to "". Records read calls.
type CompanyManagementReader struct {
	Types     map[string]string
	Err       error
	ReadCalls []string
}

func (r *CompanyManagementReader) Read(_ context.Context, companyId string) (string, error) {
	r.ReadCalls = append(r.ReadCalls, companyId)
	if r.Err != nil {
		return "", r.Err
	}
	return r.Types[companyId], nil
}

// InviteCall records one invite send.
type InviteCall struct {
	Email       string
	DisplayName string
}

// Inviter fake — records every invite. Err is returned to exercise the
// best-effort path (invite failure must not fail the request).
type Inviter struct {
	Invites []InviteCall
	Err     error
}

func (i *Inviter) Send(_ context.Context, email, displayName string) error {
	i.Invites = append(i.Invites, InviteCall{Email: email, DisplayName: displayName})
	return i.Err
}
