package triggers

import (
	"context"
	"net"
	"sort"
	"strings"
	"testing"

	"cloud.google.com/go/firestore"
	pb "cloud.google.com/go/firestore/apiv1/firestorepb"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// The update MASK is the whole finding. Firestore replaces or merges a field
// according to the paths the client puts in Write.UpdateMask, and nothing
// short of the wire can show which paths those are: firestore.SetOption is an
// opaque interface, and the leaf-collecting happens inside the client. So
// these tests stand up the smallest possible Firestore server, perform a real
// Set through the real client, and read the mask off the captured Commit.

// captureServer answers a Set and keeps the request. Everything else is left
// unimplemented — a Set is one Commit and nothing more.
type captureServer struct {
	pb.UnimplementedFirestoreServer
	commits []*pb.CommitRequest
}

func (s *captureServer) Commit(_ context.Context, req *pb.CommitRequest) (*pb.CommitResponse, error) {
	s.commits = append(s.commits, req)
	results := make([]*pb.WriteResult, len(req.GetWrites()))
	for i := range results {
		results[i] = &pb.WriteResult{UpdateTime: timestamppb.Now()}
	}
	return &pb.CommitResponse{WriteResults: results, CommitTime: timestamppb.Now()}, nil
}

// newCaptureClient returns a real firestore.Client pointed at an in-process
// fake, via FIRESTORE_EMULATOR_HOST so the client dials insecurely and never
// looks for credentials.
func newCaptureClient(t *testing.T) (*firestore.Client, *captureServer) {
	t.Helper()

	server := &captureServer{}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	grpcServer := grpc.NewServer()
	pb.RegisterFirestoreServer(grpcServer, server)
	go func() { _ = grpcServer.Serve(listener) }()
	t.Cleanup(grpcServer.Stop)

	t.Setenv("FIRESTORE_EMULATOR_HOST", listener.Addr().String())
	client, err := firestore.NewClient(context.Background(), "test-project")
	if err != nil {
		t.Fatalf("firestore client: %v", err)
	}
	t.Cleanup(func() { _ = client.Close() })

	return client, server
}

// lastUpdateMask returns the sorted field paths of the single write in the
// most recent Commit.
func lastUpdateMask(t *testing.T, server *captureServer) []string {
	t.Helper()
	if len(server.commits) != 1 {
		t.Fatalf("expected exactly 1 commit, got %d", len(server.commits))
	}
	writes := server.commits[0].GetWrites()
	if len(writes) != 1 {
		t.Fatalf("expected exactly 1 write, got %d", len(writes))
	}
	paths := append([]string(nil), writes[0].GetUpdateMask().GetFieldPaths()...)
	sort.Strings(paths)
	return paths
}

// nestedUpdatePayload is the shape BuildProductViewUpdate produces: a nested
// map (company_profile_photo_url is ImageUrl.toJson() on the Dart side), a
// scalar, an array and an explicit null.
func nestedUpdatePayload() map[string]any {
	return map[string]any{
		"company_name":              "Acme Lending",
		"company_profile_photo_url": map[string]any{"url": "b"},
		"search_tokens":             []string{"ac", "acm", "acme"},
		"deleted_at":                nil,
	}
}

// TestMergeFields_ReplacesNestedMapsWholesale is the test that closes the
// finding. The mask must name company_profile_photo_url itself, so Firestore
// replaces the whole map; a mask naming company_profile_photo_url.url merges
// into the stored map instead, and a subkey the company no longer carries
// (say a thumbnail) survives every rewrite the projection will ever make.
func TestMergeFields_ReplacesNestedMapsWholesale(t *testing.T) {
	client, server := newCaptureClient(t)
	fields := nestedUpdatePayload()

	if _, err := client.Collection("dev_product_views").Doc("view-1").
		Set(context.Background(), fields, MergeFields(fields)); err != nil {
		t.Fatalf("Set: %v", err)
	}

	got := lastUpdateMask(t, server)
	want := []string{"company_name", "company_profile_photo_url", "deleted_at", "search_tokens"}
	if len(got) != len(want) {
		t.Fatalf("update mask = %q, want %q", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("update mask = %q, want %q", got, want)
		}
	}
	for _, path := range got {
		if strings.HasPrefix(path, "company_profile_photo_url.") {
			t.Fatalf("update mask %q merges into the nested map leaf by leaf: a stale "+
				"subkey the payload no longer carries would survive forever and the view "+
				"would never converge", path)
		}
	}
}

// TestMergeAll_MergesNestedMapsLeafByLeaf pins the client behaviour MergeFields
// exists to avoid, so the reason for MergeFields cannot quietly stop being
// true. It asserts about firestore.MergeAll, not about our code.
func TestMergeAll_MergesNestedMapsLeafByLeaf(t *testing.T) {
	client, server := newCaptureClient(t)
	fields := nestedUpdatePayload()

	if _, err := client.Collection("dev_product_views").Doc("view-1").
		Set(context.Background(), fields, firestore.MergeAll); err != nil {
		t.Fatalf("Set: %v", err)
	}

	got := lastUpdateMask(t, server)
	found := false
	for _, path := range got {
		if path == "company_profile_photo_url.url" {
			found = true
		}
	}
	if !found {
		t.Fatalf("MergeAll mask = %q; expected the leaf path company_profile_photo_url.url. "+
			"If the client stopped expanding nested maps, MergeFields is no longer needed "+
			"and this test should be deleted along with it", got)
	}
}

// TestSetProductViewFields_UsesTheTopLevelMask covers the adapter the trigger
// actually runs, not just the helper it calls.
func TestSetProductViewFields_UsesTheTopLevelMask(t *testing.T) {
	client, server := newCaptureClient(t)
	views := client.Collection("dev_product_views")

	if err := setProductViewFields(context.Background(), views, "view-1", nestedUpdatePayload()); err != nil {
		t.Fatalf("setProductViewFields: %v", err)
	}

	for _, path := range lastUpdateMask(t, server) {
		if strings.HasPrefix(path, "company_profile_photo_url.") {
			t.Fatalf("the projection's update path sends %q — a leaf merge, so the view "+
				"never converges", path)
		}
	}
}

// applyWrite applies a captured write to a stored document exactly as
// Firestore's update mask specifies: each masked path is replaced by the value
// at that path in the write, and a path with no value is deleted. A top-level
// path therefore replaces a whole nested map; a dotted path reaches inside one
// and leaves its siblings alone.
func applyWrite(stored map[string]*pb.Value, write *pb.Write) {
	for _, path := range write.GetUpdateMask().GetFieldPaths() {
		parts := strings.Split(path, ".")

		fields := write.GetUpdate().GetFields()
		var value *pb.Value
		for i, part := range parts {
			value = fields[part]
			if i < len(parts)-1 {
				fields = value.GetMapValue().GetFields()
			}
		}

		target := stored
		for _, part := range parts[:len(parts)-1] {
			nested := target[part].GetMapValue().GetFields()
			if nested == nil {
				nested = map[string]*pb.Value{}
				target[part] = &pb.Value{ValueType: &pb.Value_MapValue{
					MapValue: &pb.MapValue{Fields: nested}}}
			}
			target = nested
		}

		leaf := parts[len(parts)-1]
		if value == nil {
			delete(target, leaf)
			continue
		}
		target[leaf] = value
	}
}

// TestProductViewUpdate_DropsAStaleSubkey walks the whole loop the finding is
// about: build the real update payload, send it through the real client, and
// apply the captured write the way Firestore would.
//
// The stored view holds a company photo with a thumbnail. The company now
// carries only a url. After the reprojection the thumbnail must be GONE — with
// a leaf merge it survives, the projection's whole-map comparison keeps seeing
// a difference, and every backfill pass rewrites the document forever without
// ever being able to remove it.
func TestProductViewUpdate_DropsAStaleSubkey(t *testing.T) {
	client, server := newCaptureClient(t)
	views := client.Collection("dev_product_views")

	stored := map[string]*pb.Value{
		"company_profile_photo_url": {ValueType: &pb.Value_MapValue{MapValue: &pb.MapValue{
			Fields: map[string]*pb.Value{
				"url":       {ValueType: &pb.Value_StringValue{StringValue: "a"}},
				"thumbnail": {ValueType: &pb.Value_StringValue{StringValue: "t"}},
			},
		}}},
	}

	product := map[string]any{"id": "product-1", "provider_id": "company-1"}
	company := map[string]any{
		"name":                      "Acme Lending",
		"company_profile_photo_url": map[string]any{"url": "b"},
	}

	fields := BuildProductViewUpdate(product, company, 1755000000000)
	if err := setProductViewFields(context.Background(), views, "view-1", fields); err != nil {
		t.Fatalf("setProductViewFields: %v", err)
	}
	if len(server.commits) != 1 || len(server.commits[0].GetWrites()) != 1 {
		t.Fatalf("expected one write, got commits=%d", len(server.commits))
	}
	applyWrite(stored, server.commits[0].GetWrites()[0])

	photo := stored["company_profile_photo_url"].GetMapValue().GetFields()
	if _, stale := photo["thumbnail"]; stale {
		t.Errorf("thumbnail survived the reprojection: the company no longer carries it, "+
			"so the view can never converge and every backfill pass rewrites it. stored = %v", photo)
	}
	if got := photo["url"].GetStringValue(); got != "b" {
		t.Errorf("url = %q, want %q", got, "b")
	}
	if len(photo) != 1 {
		t.Errorf("company_profile_photo_url = %v, want exactly the company's own {url}", photo)
	}
}

// An empty payload must not reach Firestore at all: firestore.Merge with no
// paths still produces a write, which bumps the document and re-fires the
// trigger for nothing.
func TestSetProductViewFields_WritesNothingForAnEmptyPayload(t *testing.T) {
	client, server := newCaptureClient(t)
	views := client.Collection("dev_product_views")

	if err := setProductViewFields(context.Background(), views, "view-1", map[string]any{}); err != nil {
		t.Fatalf("setProductViewFields: %v", err)
	}
	if len(server.commits) != 0 {
		t.Fatalf("expected no commit for an empty payload, got %d", len(server.commits))
	}
}
