// validate-wpr checks stored top-level navigations without starting WPR.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"html"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"go.chromium.org/webpagereplay/src/webpagereplay"
	"golang.org/x/net/publicsuffix"
)

const maxRedirects = 10

var (
	titlePattern = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)
	spacePattern = regexp.MustCompile(`\s+`)
	blockMarkers = []string{
		"access denied",
		"attention required",
		"checking your browser",
		"request blocked",
		"temporarily blocked",
		"unusual traffic",
		"verify you are human",
	}
)

type archivedResponse struct {
	status      int
	location    string
	contentType string
	body        []byte
	decodeError string
}

type pathResult struct {
	valid       bool
	statuses    []int
	finalURL    string
	contentType string
	title       string
	marker      string
	reason      string
}

type siteResult struct {
	site         string
	archive      string
	sha256       string
	archiveBytes int64
	verdict      string
	statusChains []string
	finalURLs    []string
	contentTypes []string
	titles       []string
	markers      []string
	reasons      []string
}

func main() {
	var sitesCSV, sitesFile, archiveDir, manifestPath, reportPath string
	flag.StringVar(&sitesCSV, "sites", "", "comma-separated sites; overrides --sites-file")
	flag.StringVar(&sitesFile, "sites-file", "", "newline-separated default site list")
	flag.StringVar(&archiveDir, "archive-dir", "", "directory containing navToLCP_<site>.wprgo")
	flag.StringVar(&manifestPath, "manifest", "", "output TSV manifest")
	flag.StringVar(&reportPath, "report", "", "output actionable text report")
	flag.Parse()

	if archiveDir == "" || manifestPath == "" || reportPath == "" {
		fatalUsage("--archive-dir, --manifest, and --report are required")
	}
	sites, err := loadSites(sitesCSV, sitesFile)
	if err != nil {
		fatalUsage(err.Error())
	}

	results := make([]siteResult, 0, len(sites))
	ok, siteErrors := 0, 0
	for _, site := range sites {
		result := validateSite(site, filepath.Join(archiveDir, archiveName(site)))
		switch result.verdict {
		case "ok":
			ok++
		default:
			siteErrors++
		}
		results = append(results, result)
	}

	if err := writeManifest(manifestPath, results); err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: write manifest: %v\n", err)
		os.Exit(2)
	}
	if err := writeReport(reportPath, results); err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: write report: %v\n", err)
		os.Exit(2)
	}

	fmt.Printf("WPR archive validation: %d ok, %d error\n", ok, siteErrors)
	for _, result := range results {
		fmt.Printf("  %-9s %-24s %s\n", strings.ToUpper(result.verdict), result.site, strings.Join(result.statusChains, " | "))
	}
	if ok == 0 {
		fmt.Fprintln(os.Stderr, "ERROR: package validation failed: no sites are eligible for measurement")
		os.Exit(1)
	}
}

func fatalUsage(message string) {
	fmt.Fprintf(os.Stderr, "ERROR: %s\n", message)
	flag.Usage()
	os.Exit(2)
}

func loadSites(csv, path string) ([]string, error) {
	var values []string
	if strings.TrimSpace(csv) != "" {
		values = strings.Split(csv, ",")
	} else {
		if path == "" {
			return nil, errors.New("--sites or --sites-file is required")
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read sites file: %w", err)
		}
		values = strings.Split(string(data), "\n")
	}

	seen := make(map[string]bool)
	sites := make([]string, 0, len(values))
	for _, value := range values {
		site := strings.ToLower(strings.TrimSpace(value))
		if site == "" || strings.HasPrefix(site, "#") {
			continue
		}
		if strings.ContainsAny(site, "/:?# \t") {
			return nil, fmt.Errorf("site must be a hostname, got %q", site)
		}
		if seen[site] {
			return nil, fmt.Errorf("duplicate site %q", site)
		}
		seen[site] = true
		sites = append(sites, site)
	}
	if len(sites) == 0 {
		return nil, errors.New("site list is empty")
	}
	return sites, nil
}

func archiveName(site string) string {
	name := strings.NewReplacer("+", "_", "/", "_").Replace("navToLCP+" + site)
	return name + ".wprgo"
}

func validateSite(site, archivePath string) siteResult {
	result := siteResult{site: site, archive: filepath.Base(archivePath), verdict: "error"}
	info, err := os.Stat(archivePath)
	if err != nil {
		result.reasons = []string{"archive_missing"}
		return result
	}
	result.archiveBytes = info.Size()
	result.sha256, err = fileSHA256(archivePath)
	if err != nil {
		result.reasons = []string{"archive_unreadable: " + err.Error()}
		return result
	}

	archive, err := webpagereplay.OpenArchive(archivePath)
	if err != nil {
		result.reasons = []string{"archive_corrupt: " + err.Error()}
		return result
	}
	responses := make(map[string][]archivedResponse)
	initialURL := "https://" + site + "/"
	if err := archive.ForEach(func(request *http.Request, response *http.Response) error {
		if request.Body != nil {
			defer request.Body.Close()
		}
		if response.Body != nil {
			defer response.Body.Close()
		}
		if request.Method != http.MethodGet {
			return nil
		}
		key, err := canonicalURL(request.URL)
		if err != nil {
			return nil
		}
		isNavigation := strings.EqualFold(request.Header.Get("Sec-Fetch-Dest"), "document") ||
			strings.EqualFold(request.Header.Get("Sec-Fetch-Mode"), "navigate") ||
			key == initialURL
		if !isNavigation {
			return nil
		}
		item := archivedResponse{
			status:      response.StatusCode,
			location:    response.Header.Get("Location"),
			contentType: response.Header.Get("Content-Type"),
		}
		if err := webpagereplay.DecompressResponse(response); err != nil {
			item.decodeError = err.Error()
		} else {
			body, err := io.ReadAll(response.Body)
			if err != nil {
				item.decodeError = "read response body: " + err.Error()
			} else {
				item.body = body
			}
		}
		responses[key] = append(responses[key], item)
		return nil
	}); err != nil {
		result.reasons = []string{"archive_unreadable: " + err.Error()}
		return result
	}
	paths := validatePaths(initialURL, site, responses, nil, 0)
	if len(paths) == 0 {
		paths = []pathResult{{reason: "main_document_missing"}}
	}
	valid := true
	for _, path := range paths {
		result.statusChains = appendUnique(result.statusChains, formatStatuses(path.statuses))
		result.finalURLs = appendUnique(result.finalURLs, path.finalURL)
		result.contentTypes = appendUnique(result.contentTypes, path.contentType)
		result.titles = appendUnique(result.titles, path.title)
		result.markers = appendUnique(result.markers, path.marker)
		result.reasons = appendUnique(result.reasons, path.reason)
		if !path.valid {
			valid = false
		}
	}
	if !valid && len(result.reasons) == 0 {
		result.reasons = []string{"unknown_validation_failure"}
	}
	if valid {
		result.verdict = "ok"
	}
	return result
}

func validatePaths(rawURL, originalSite string, responses map[string][]archivedResponse, visited map[string]bool, depth int) []pathResult {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return []pathResult{{finalURL: rawURL, reason: "invalid_url: " + err.Error()}}
	}
	key, err := canonicalURL(parsed)
	if err != nil {
		return []pathResult{{finalURL: rawURL, reason: "invalid_url: " + err.Error()}}
	}
	if depth > maxRedirects {
		return []pathResult{{finalURL: key, reason: "too_many_redirects"}}
	}
	if visited[key] {
		return []pathResult{{finalURL: key, reason: "redirect_cycle"}}
	}
	nextVisited := cloneVisited(visited)
	nextVisited[key] = true

	candidates := responses[key]
	if len(candidates) == 0 {
		reason := "main_document_missing"
		if depth > 0 {
			reason = "redirect_target_missing"
		}
		return []pathResult{{finalURL: key, reason: reason}}
	}

	var paths []pathResult
	for _, response := range candidates {
		base := pathResult{statuses: []int{response.status}, finalURL: key}
		switch {
		case response.status >= 300 && response.status < 400:
			if response.location == "" {
				base.reason = "redirect_location_missing"
				paths = append(paths, base)
				continue
			}
			target, err := parsed.Parse(response.location)
			if err != nil {
				base.reason = "invalid_redirect_location"
				paths = append(paths, base)
				continue
			}
			if !sameRegistrableDomain(originalSite, target.Hostname()) {
				base.finalURL = target.String()
				base.reason = "unexpected_offsite_redirect"
				paths = append(paths, base)
				continue
			}
			children := validatePaths(target.String(), originalSite, responses, nextVisited, depth+1)
			for _, child := range children {
				child.statuses = append(base.statuses, child.statuses...)
				paths = append(paths, child)
			}
		case response.status >= 200 && response.status < 300:
			base.contentType = response.contentType
			base.title = extractTitle(response.body)
			if !isHTML(response.contentType) {
				base.reason = "final_response_not_html"
			} else if strings.HasPrefix(response.decodeError, "unknown compression:") {
				base.reason = "response_body_uninspectable: " + response.decodeError
			} else if response.decodeError != "" {
				base.reason = "response_body_unreadable: " + response.decodeError
			} else if len(response.body) == 0 {
				base.reason = "final_response_empty"
			} else if marker := findBlockMarker(base.title, response.body); marker != "" {
				base.marker = marker
				base.reason = "block_page_detected"
			} else {
				base.valid = true
			}
			paths = append(paths, base)
		default:
			base.contentType = response.contentType
			base.title = extractTitle(response.body)
			base.marker = findBlockMarker(base.title, response.body)
			base.reason = fmt.Sprintf("http_%d", response.status)
			paths = append(paths, base)
		}
	}
	return paths
}

func canonicalURL(value *url.URL) (string, error) {
	if value == nil || value.Scheme == "" || value.Host == "" {
		return "", errors.New("URL has no scheme or host")
	}
	copy := *value
	copy.Scheme = strings.ToLower(copy.Scheme)
	copy.Host = strings.ToLower(copy.Host)
	if (copy.Scheme == "https" && copy.Port() == "443") || (copy.Scheme == "http" && copy.Port() == "80") {
		copy.Host = copy.Hostname()
	}
	if copy.Path == "" {
		copy.Path = "/"
	}
	copy.Fragment = ""
	return copy.String(), nil
}

func sameRegistrableDomain(left, right string) bool {
	left = strings.ToLower(strings.TrimSuffix(left, "."))
	right = strings.ToLower(strings.TrimSuffix(right, "."))
	if left == right {
		return true
	}
	leftDomain, leftErr := publicsuffix.EffectiveTLDPlusOne(left)
	rightDomain, rightErr := publicsuffix.EffectiveTLDPlusOne(right)
	return leftErr == nil && rightErr == nil && leftDomain == rightDomain
}

func isHTML(contentType string) bool {
	mediaType, _, err := mime.ParseMediaType(contentType)
	if err != nil {
		mediaType = strings.TrimSpace(strings.Split(contentType, ";")[0])
	}
	return strings.EqualFold(mediaType, "text/html") ||
		strings.EqualFold(mediaType, "application/xhtml+xml")
}

func extractTitle(body []byte) string {
	match := titlePattern.FindSubmatch(body)
	if len(match) < 2 {
		return ""
	}
	title := html.UnescapeString(string(match[1]))
	return strings.TrimSpace(spacePattern.ReplaceAllString(title, " "))
}

func findBlockMarker(title string, body []byte) string {
	lowerTitle := strings.ToLower(title)
	for _, marker := range blockMarkers {
		if strings.Contains(lowerTitle, marker) {
			return marker
		}
	}
	// Keep body matching conservative: short error/challenge pages are useful
	// signals, while a normal large page may legitimately mention these words.
	if len(body) <= 32*1024 {
		lowerBody := strings.ToLower(string(body))
		for _, marker := range blockMarkers {
			if strings.Contains(lowerBody, marker) {
				return marker
			}
		}
	}
	return ""
}

func cloneVisited(input map[string]bool) map[string]bool {
	output := make(map[string]bool, len(input)+1)
	for key, value := range input {
		output[key] = value
	}
	return output
}

func fileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func formatStatuses(statuses []int) string {
	if len(statuses) == 0 {
		return "-"
	}
	values := make([]string, len(statuses))
	for index, status := range statuses {
		values[index] = fmt.Sprintf("%d", status)
	}
	return strings.Join(values, " -> ")
}

func appendUnique(values []string, value string) []string {
	if value == "" {
		return values
	}
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}

func writeManifest(path string, results []siteResult) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := fmt.Fprintln(file, "site\tarchive\tsha256\tarchive_bytes\tverdict\treason_code\thttp_status\tdetail\tstatus_chain\tfinal_url\tcontent_type\tblocked_marker"); err != nil {
		return err
	}
	for _, result := range results {
		fields := []string{
			result.site,
			result.archive,
			result.sha256,
			fmt.Sprintf("%d", result.archiveBytes),
			result.verdict,
			primaryReasonCode(result.reasons),
			primaryHTTPStatus(result.reasons),
			strings.Join(result.reasons, " | "),
			strings.Join(result.statusChains, " | "),
			strings.Join(result.finalURLs, " | "),
			strings.Join(result.contentTypes, " | "),
			strings.Join(result.markers, " | "),
		}
		for index := range fields {
			fields[index] = sanitizeTSV(fields[index])
		}
		if _, err := fmt.Fprintln(file, strings.Join(fields, "\t")); err != nil {
			return err
		}
	}
	return file.Close()
}

func primaryReasonCode(reasons []string) string {
	if len(reasons) == 0 {
		return ""
	}
	return strings.SplitN(reasons[0], ": ", 2)[0]
}

func primaryHTTPStatus(reasons []string) string {
	code := primaryReasonCode(reasons)
	if strings.HasPrefix(code, "http_") && len(code) == len("http_")+3 {
		return strings.TrimPrefix(code, "http_")
	}
	return ""
}

func writeReport(path string, results []siteResult) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	ok, siteErrors := 0, 0
	for _, result := range results {
		if result.verdict == "ok" {
			ok++
		} else {
			siteErrors++
		}
	}
	packageStatus := "READY"
	if ok == 0 {
		packageStatus = "FAILED"
	}
	var report strings.Builder
	fmt.Fprintf(&report, "WPR archive validation: COMPLETE\n")
	fmt.Fprintf(&report, "Package status: %s\n", packageStatus)
	fmt.Fprintf(&report, "Eligible sites: %d/%d\n", ok, len(results))
	fmt.Fprintf(&report, "Site errors: %d\n", siteErrors)
	fmt.Fprintf(&report, "Detected issues: %d\n\n", siteErrors)
	for _, result := range results {
		if result.verdict == "ok" {
			continue
		}
		fmt.Fprintf(&report, "[%s] %s\n", strings.ToUpper(result.verdict), result.site)
		fmt.Fprintf(&report, "Archive: %s\n", result.archive)
		if result.sha256 != "" {
			fmt.Fprintf(&report, "SHA-256: %s\n", result.sha256)
		}
		fmt.Fprintf(&report, "Status chain: %s\n", valueOrDash(strings.Join(result.statusChains, " | ")))
		fmt.Fprintf(&report, "Final URL: %s\n", valueOrDash(strings.Join(result.finalURLs, " | ")))
		fmt.Fprintf(&report, "Content-Type: %s\n", valueOrDash(strings.Join(result.contentTypes, " | ")))
		if len(result.titles) != 0 {
			fmt.Fprintf(&report, "Title: %s\n", strings.Join(result.titles, " | "))
		}
		if len(result.markers) != 0 {
			fmt.Fprintf(&report, "Block marker: %s\n", strings.Join(result.markers, " | "))
		}
		fmt.Fprintf(&report, "Failure: %s\n", strings.Join(result.reasons, " | "))
		fmt.Fprintf(&report, "Action: %s\n\n", remediation(result.reasons))
	}
	if ok == 0 {
		report.WriteString("Browser jobs will not start because no configured site passed archive validation.\n")
	} else {
		report.WriteString("Browser jobs will measure only sites with an OK archive.\n")
	}
	return os.WriteFile(path, []byte(report.String()), 0o644)
}

func remediation(reasons []string) string {
	joined := strings.Join(reasons, " ")
	switch {
	case strings.Contains(joined, "archive_missing"):
		return "publish the missing archive, or correct the configured site/archive name"
	case strings.Contains(joined, "archive_corrupt"), strings.Contains(joined, "archive_unreadable"):
		return "redownload the archive; if it remains unreadable, replace the source artifact"
	case strings.Contains(joined, "main_document_missing"):
		return "correct the configured URL or re-record the archive with the top-level navigation"
	case strings.Contains(joined, "redirect_target_missing"):
		return "re-record the archive so the complete navigation redirect chain is present"
	case strings.Contains(joined, "unexpected_offsite_redirect"):
		return "review the redirect; correct the URL or replace a recording that landed on consent/login/blocking infrastructure"
	case strings.Contains(joined, "block_page_detected"), strings.Contains(joined, "http_403"), strings.Contains(joined, "http_429"):
		return "replace or re-record the archive under conditions that do not capture bot blocking"
	case strings.Contains(joined, "http_5"):
		return "replace or re-record the archive; it captured a server failure"
	case strings.Contains(joined, "final_response_not_html"):
		return "correct the URL or replace the malformed recording"
	default:
		return "inspect the manifest and replace or re-record the failed navigation"
	}
}

func sanitizeTSV(value string) string {
	return strings.NewReplacer("\t", " ", "\r", " ", "\n", " ").Replace(value)
}

func valueOrDash(value string) string {
	if value == "" {
		return "-"
	}
	return value
}

func init() {
	webpagereplay.SetLogLevel("ERROR")
}
