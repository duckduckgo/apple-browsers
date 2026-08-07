package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestManifestReasonFields(t *testing.T) {
	tests := []struct {
		reasons []string
		code    string
		status  string
	}{
		{nil, "", ""},
		{[]string{"archive_missing"}, "archive_missing", ""},
		{[]string{"archive_corrupt: unexpected EOF"}, "archive_corrupt", ""},
		{[]string{"http_403"}, "http_403", "403"},
	}
	for _, test := range tests {
		if got := primaryReasonCode(test.reasons); got != test.code {
			t.Errorf("primaryReasonCode(%q) = %q, want %q", test.reasons, got, test.code)
		}
		if got := primaryHTTPStatus(test.reasons); got != test.status {
			t.Errorf("primaryHTTPStatus(%q) = %q, want %q", test.reasons, got, test.status)
		}
	}
}

func TestManifestCarriesMachineReadableFailureAndArchiveIdentity(t *testing.T) {
	path := filepath.Join(t.TempDir(), "manifest.tsv")
	result := siteResult{
		site:         "blocked.test",
		archive:      "navToLCP_blocked.test.wprgo",
		sha256:       strings.Repeat("a", 64),
		archiveBytes: 42,
		verdict:      "error",
		reasons:      []string{"http_403"},
	}
	if err := writeManifest(path, []siteResult{result}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	wantHeader := "site\tarchive\tsha256\tarchive_bytes\tverdict\treason_code\thttp_status\tdetail\tstatus_chain\tfinal_url\tcontent_type\tblocked_marker"
	if lines[0] != wantHeader {
		t.Fatalf("header = %q, want %q", lines[0], wantHeader)
	}
	fields := strings.Split(lines[1], "\t")
	if fields[2] != result.sha256 || fields[5] != "http_403" || fields[6] != "403" {
		t.Fatalf("unexpected manifest fields: %q", fields)
	}
}
