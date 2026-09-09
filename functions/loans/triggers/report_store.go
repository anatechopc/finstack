package triggers

import (
	"context"
	"fmt"
	"strings"
	"time"

	"firebase.google.com/go/v4/db"
)

// rtdbReportStore is the production ReportStore on the Realtime Database.
type rtdbReportStore struct {
	client *db.Client
}

// NewRTDBReportStore wraps a Realtime Database client.
func NewRTDBReportStore(client *db.Client) ReportStore {
	return &rtdbReportStore{client: client}
}

// keySafe strips the characters a Realtime Database key may not contain.
var keySafe = strings.NewReplacer(".", "_", "#", "_", "$", "_", "[", "_", "]", "_", "/", "_")

// reportEventKey is the claim node, a sibling of report_summary so the
// client, which streams report_summary in full, never downloads the claims.
func reportEventKey(eventId string) string {
	return "report_events/" + keySafe.Replace(eventId)
}

// ClaimEvent runs DecideClaim inside a transaction, so two deliveries of the
// same event cannot both win.
func (s *rtdbReportStore) ClaimEvent(ctx context.Context, basePath, eventId string, now time.Time) (ClaimResult, error) {
	result := ClaimInProgress
	path := basePath + "/" + reportEventKey(eventId)
	err := s.client.NewRef(path).Transaction(ctx, func(node db.TransactionNode) (any, error) {
		var current *ClaimRecord
		if err := node.Unmarshal(&current); err != nil {
			return nil, err
		}
		var next ClaimRecord
		result, next = DecideClaim(current, now)
		return next, nil
	})
	if err != nil {
		return ClaimInProgress, fmt.Errorf("transaction on %s: %w", path, err)
	}
	return result, nil
}

func (s *rtdbReportStore) ProductType(ctx context.Context, basePath, loanId string) (string, error) {
	path := basePath + "/loans/" + loanId + ":product_type"
	var productType string
	if err := s.client.NewRef(path).Get(ctx, &productType); err != nil {
		return "", fmt.Errorf("read %s: %w", path, err)
	}
	if productType == "" {
		return "", fmt.Errorf("product type not found at %s", path)
	}
	return productType, nil
}

// Apply writes every increment, every data item and the event's applied
// marker in ONE multi-path update on the company node. The counters use the
// server-side increment, so concurrent writers never read-modify-write
// (campaign D2), and the update is all-or-nothing.
func (s *rtdbReportStore) Apply(ctx context.Context, basePath, eventId string, now time.Time, plan ReportPlan) error {
	update := make(map[string]any, len(plan.Increments)+len(plan.Items)+1)
	for path, delta := range plan.Increments {
		update["report_summary/"+path] = map[string]any{".sv": map[string]any{"increment": delta}}
	}
	for _, item := range plan.Items {
		update["report_summary/data/"+item.Key] = item.Item
	}
	update[reportEventKey(eventId)] = map[string]any{"applied": true, "applied_at": now.UnixMilli()}
	if err := s.client.NewRef(basePath).Update(ctx, update); err != nil {
		return fmt.Errorf("multi-path update of %s: %w", basePath, err)
	}
	return nil
}
