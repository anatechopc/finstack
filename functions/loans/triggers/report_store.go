package triggers

import (
	"context"
	"fmt"

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

func appliedEventPath(basePath, eventId string) string {
	return basePath + "/report_summary/applied_events/" + eventId
}

// ClaimEvent sets the event marker inside a transaction, so two deliveries of
// the same event cannot both win.
func (s *rtdbReportStore) ClaimEvent(ctx context.Context, basePath, eventId string) (bool, error) {
	claimed := false
	err := s.client.NewRef(appliedEventPath(basePath, eventId)).Transaction(ctx, func(node db.TransactionNode) (any, error) {
		var current any
		if err := node.Unmarshal(&current); err != nil {
			return nil, err
		}
		if current != nil {
			claimed = false
			return current, nil
		}
		claimed = true
		return true, nil
	})
	if err != nil {
		return false, fmt.Errorf("transaction on %s: %w", appliedEventPath(basePath, eventId), err)
	}
	return claimed, nil
}

func (s *rtdbReportStore) ReleaseEvent(ctx context.Context, basePath, eventId string) error {
	return s.client.NewRef(appliedEventPath(basePath, eventId)).Delete(ctx)
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

// Apply writes every increment and data item in ONE multi-path update. The
// counters use the server-side increment, so concurrent writers never
// read-modify-write (campaign D2), and the update is all-or-nothing.
func (s *rtdbReportStore) Apply(ctx context.Context, basePath string, plan ReportPlan) error {
	if plan.IsEmpty() {
		return nil
	}
	update := make(map[string]any, len(plan.Increments)+len(plan.Items))
	for path, delta := range plan.Increments {
		update[path] = map[string]any{".sv": map[string]any{"increment": delta}}
	}
	for _, item := range plan.Items {
		update["data/"+item.Key] = item.Item
	}
	if err := s.client.NewRef(basePath+"/report_summary").Update(ctx, update); err != nil {
		return fmt.Errorf("multi-path update of %s/report_summary: %w", basePath, err)
	}
	return nil
}
