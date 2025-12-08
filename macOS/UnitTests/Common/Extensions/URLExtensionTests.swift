//
//  URLExtensionTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation
import Testing

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class URLExtensionTests {

    @Test("Verifying non-sandbox library directory URL returns consistent value regardless of sandbox")
    func thatNonSandboxLibraryDirectoryURLReturnsTheSameValueRegardlessOfSandbox() {
        let libraryURL = URL.nonSandboxLibraryDirectoryURL
        var pathComponents = libraryURL.path.components(separatedBy: "/")
        #expect(pathComponents.count == 4)

        pathComponents[2] = "user"

        #expect(pathComponents == ["", "Users", "user", "Library"])
    }

    @Test("Verifying non-sandbox application support directory URL returns consistent value regardless of sandbox")
    func thatNonSandboxApplicationSupportDirectoryURLReturnsTheSameValueRegardlessOfSandbox() {
        let libraryURL = URL.nonSandboxApplicationSupportDirectoryURL
        var pathComponents = libraryURL.path.components(separatedBy: "/")
        #expect(pathComponents.count == 5)

        pathComponents[2] = "user"

        #expect(pathComponents == ["", "Users", "user", "Library", "Application Support"])
    }

    static let makeURL_from_addressBarString_args = [
        ("regular-domain.com/path/to/directory/", "http://regular-domain.com/path/to/directory/", #line),
        ("regular-domain.com", "http://regular-domain.com", #line),
        ("regular-domain.com/", "http://regular-domain.com/", #line),
        ("regular-domain.com/filename", "http://regular-domain.com/filename", #line),
        ("regular-domain.com/filename?a=b&b=c", "http://regular-domain.com/filename?a=b&b=c", #line),
        ("regular-domain.com/filename/?a=b&b=c", "http://regular-domain.com/filename/?a=b&b=c", #line),
        ("http://regular-domain.com?a=b&b=c", "http://regular-domain.com?a=b&b=c", #line),
        ("http://regular-domain.com/?a=b&b=c", "http://regular-domain.com/?a=b&b=c", #line),
        ("https://hexfiend.com/file?q=a", "https://hexfiend.com/file?q=a", #line),
        ("https://hexfiend.com/file/?q=a", "https://hexfiend.com/file/?q=a", #line),
        ("https://hexfiend.com/?q=a", "https://hexfiend.com/?q=a", #line),
        ("https://hexfiend.com?q=a", "https://hexfiend.com?q=a", #line),
        ("regular-domain.com/path/to/file ", "http://regular-domain.com/path/to/file", #line),
        ("search string with spaces", "https://duckduckgo.com/?q=search+string+with+spaces", #line),
        ("https://duckduckgo.com/?q=search string with spaces&arg 2=val 2", "https://duckduckgo.com/?q=search%20string%20with%20spaces&arg%202=val%202", #line),
        ("https://duckduckgo.com/?q=search+string+with+spaces", "https://duckduckgo.com/?q=search+string+with+spaces", #line),
        ("https://screwjankgames.github.io/engine programming/2020/09/24/writing-your.html", "https://screwjankgames.github.io/engine%20programming/2020/09/24/writing-your.html", #line),
        ("define: foo", "https://duckduckgo.com/?q=define%3A+foo", #line),
        ("test://hello/", "test://hello/", #line),
        ("localdomain", "https://duckduckgo.com/?q=localdomain", #line),
        ("   http://example.com\n", "http://example.com", #line),
        (" duckduckgo.com", "http://duckduckgo.com", #line),
        (" duck duck go.c ", "https://duckduckgo.com/?q=duck+duck+go.c", #line),
        ("localhost ", "http://localhost", #line),
        ("local ", "https://duckduckgo.com/?q=local", #line),
        ("test string with spaces", "https://duckduckgo.com/?q=test+string+with+spaces", #line),
        ("http://💩.la:8080 ", "http://xn--ls8h.la:8080", #line),
        ("http:// 💩.la:8080 ", "https://duckduckgo.com/?q=http%3A%2F%2F+%F0%9F%92%A9.la%3A8080", #line),
        ("https://xn--ls8h.la/path/to/resource", "https://xn--ls8h.la/path/to/resource", #line),
        ("1.4/3.4", "https://duckduckgo.com/?q=1.4%2F3.4", #line),
        ("16385-12228.72", "https://duckduckgo.com/?q=16385-12228.72", #line),
        ("user@localhost", "https://duckduckgo.com/?q=user%40localhost", #line),
        ("user@domain.com", "https://duckduckgo.com/?q=user%40domain.com", #line),
        ("http://user@domain.com", "http://user@domain.com", #line),
        ("http://user:@domain.com", "http://user:@domain.com", #line),
        ("http://user: @domain.com", "http://user:%20@domain.com", #line),
        ("http://user:,,@domain.com", "http://user:,,@domain.com", #line),
        ("http://user:pass@domain.com", "http://user:pass@domain.com", #line),
        ("http://user name:pass word@domain.com/folder name/file name/", "http://user%20name:pass%20word@domain.com/folder%20name/file%20name/", #line),
        ("1+(3+4*2)", "https://duckduckgo.com/?q=1%2B%283%2B4%2A2%29", #line),
    ]
    @Test("Creating URLs from address bar strings", arguments: makeURL_from_addressBarString_args)
    func makeURL_from_addressBarString(string: String, expectation: String, line: Int) {
        let url = URL.makeURLUsingNativePredictionLogic(from: string)!
        #expect(expectation == url.absoluteString, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    static let sanitizedForQuarantine_args = [
        ("file:///local/file/name", nil, #line),
        ("http://example.com", "http://example.com", #line),
        ("https://duckduckgo.com", "https://duckduckgo.com", #line),
        ("data://asdfgb", nil, #line),
        ("localhost", "localhost", #line),
        ("blob://afasdg", nil, #line),
        ("http://user:pass@duckduckgo.com", "http://duckduckgo.com", #line),
        ("https://user:pass@duckduckgo.com", "https://duckduckgo.com", #line),
        ("https://user:pass@releases.usercontent.com/asdfg?arg=AWS4-HMAC&Credential=AKIA",
         "https://releases.usercontent.com/asdfg?arg=AWS4-HMAC&Credential=AKIA", #line),
        ("ftp://user:pass@duckduckgo.com", "ftp://duckduckgo.com", #line),
    ]
    @Test("Sanitizing URLs for quarantine", arguments: sanitizedForQuarantine_args)
    func sanitizedForQuarantine(string: String, expectation: String?, line: Int) {
        let url = URL(string: string)!.sanitizedForQuarantine()
        #expect(url?.absoluteString == expectation, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    static let whenOneSlashIsMissingAfterHypertextScheme_ThenItShouldBeAdded_args = [
        ("http:/duckduckgo.com", "http://duckduckgo.com", #line),
        ("http://duckduckgo.com", "http://duckduckgo.com", #line),
        ("https:/duckduckgo.com", "https://duckduckgo.com", #line),
        ("https://duckduckgo.com", "https://duckduckgo.com", #line),
        ("file:/Users/user/file.txt", "file:/Users/user/file.txt", #line),
        ("file://domain/file.txt", "file://domain/file.txt", #line),
        ("file:///Users/user/file.txt", "file:///Users/user/file.txt", #line),
    ]
    @Test("Adding missing slash after hypertext scheme", arguments: whenOneSlashIsMissingAfterHypertextScheme_ThenItShouldBeAdded_args)
    func whenOneSlashIsMissingAfterHypertextScheme_ThenItShouldBeAdded(string: String, expectation: String, line: Int) {
        let url = URL.makeURLUsingNativePredictionLogic(from: string)
        #expect(url?.absoluteString == expectation, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @Test("Verifying hypertext scheme when making URL from suggestion phrase with colon")
    func whenMakingUrlFromSuggestionPhaseContainingColon_ThenVerifyHypertextScheme() {
        let validUrl = URL.makeURL(fromSuggestionPhrase: "http://duckduckgo.com")
        #expect(validUrl != nil)
        #expect(validUrl?.scheme == "http")

        let anotherValidUrl = URL.makeURL(fromSuggestionPhrase: "duckduckgo.com")
        #expect(anotherValidUrl != nil)
        #expect(validUrl?.scheme != nil)

        let notURL = URL.makeURL(fromSuggestionPhrase: "type:pdf")
        #expect(notURL == nil)
    }

    @Test("Extracting comma-separated email addresses from mailto URL")
    func thatEmailAddressesExtractsCommaSeparatedAddressesFromMailtoURL() throws {
        let url1 = try #require(URL(string: "mailto:dax@duck.com,donald@duck.com,example@duck.com"))
        #expect(url1.emailAddresses == ["dax@duck.com", "donald@duck.com", "example@duck.com"])

        if let url2 = URL(string: "mailto:  dax@duck.com,    donald@duck.com,  example@duck.com ") {
            #expect(url2.emailAddresses == ["dax@duck.com", "donald@duck.com", "example@duck.com"])
        }
    }

    @Test("Extracting invalid email addresses from mailto URLs")
    func thatEmailAddressesExtractsInvalidEmailAddresses() throws {
        // parity with Safari which also doesn't validate email addresses
        let url1 = try #require(URL(string: "mailto:dax@duck.com,donald,example"))
        #expect(url1.emailAddresses == ["dax@duck.com", "donald", "example"])

        if let url2 = URL(string: "mailto:dax@duck.com, ,,, ,, donald") {
            #expect(url2.emailAddresses == ["dax@duck.com", "donald"])
        }
    }

    @Test("Returning host and port when port is specified")
    func whenGetHostAndPort_WithPort_ThenHostAndPortIsReturned() throws {
        // Given
        let expected = "duckduckgo.com:1234"
        let sut = URL(string: "https://duckduckgo.com:1234")

        // When
        let result = sut?.hostAndPort()

        // Then
        #expect(expected == result)
    }

    @Test("Returning only host when port is not specified")
    func whenGetHostAndPort_WithoutPort_ThenHostReturned() throws {
        // Given
        let expected = "duckduckgo.com"
        let sut = URL(string: "https://duckduckgo.com")

        // When
        let result = sut?.hostAndPort()

        // Then
        #expect(expected == result)
    }

    @Test("Checking if URL is child of itself")
    func isChildWhenURLsSame() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://duckduckgo.com/subscriptions")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Checking if URL with subpath is child of parent URL")
    func isChildWhenTestedURLHasSubpath() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://dax.duckduckgo.com/subscriptions/test")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Checking if URL with subdomain is child of parent URL")
    func isChildWhenTestedURLHasSubdomain() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://dax.duckduckgo.com/subscriptions")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Checking if URL with subdomain and subpath is child of parent URL")
    func isChildWhenTestedURLHasSubdomainAndSubpath() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://dax.duckduckgo.com/subscriptions/test")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Checking if URL with www subdomain is child of parent URL")
    func isChildWhenTestedURLHasWWW() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://www.duckduckgo.com/subscriptions/test/t")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Checking if URL is child of parent URL when parent has parameters that should be ignored")
    func isChildWhenParentHasParamThatShouldBeIgnored() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions?environment=staging")!
        let testedURL = URL(string: "https://www.duckduckgo.com/subscriptions/test/t")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Checking if URL with parameters is child of parent URL when parameters should be ignored")
    func isChildWhenChildHasParamThatShouldBeIgnored() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://duckduckgo.com/subscriptions?environment=staging")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Checking if URL with path and parameters is child of parent URL when parameters should be ignored")
    func isChildWhenChildHasPathAndParamThatShouldBeIgnored() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://www.duckduckgo.com/subscriptions/test/t?environment=staging")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Checking if URL is child of parent URL when both have parameters that should be ignored")
    func isChildWhenBothHaveParamThatShouldBeIgnored() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions?environment=production")!
        let testedURL = URL(string: "https://www.duckduckgo.com/subscriptions/test/t?environment=staging")!
        #expect(testedURL.isChild(of: parentURL) == true)
    }

    @Test("Verifying URL is not child of parent URL when path is shorter substring")
    func isChildFailsWhenPathIsShorterSubstring() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://duckduckgo.com/subscription")!
        #expect(testedURL.isChild(of: parentURL) == false)
    }

    @Test("Verifying URL is not child of parent URL when path is longer but not proper subpath")
    func isChildFailsWhenPathIsLonger() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let testedURL = URL(string: "https://duckduckgo.com/subscriptionszzz")!
        #expect(testedURL.isChild(of: parentURL) == false)
    }

    @Test("Verifying URL is not child of parent URL when child path is incomplete")
    func isChildFailsWhenPathIsNotComplete() throws {
        let parentURL = URL(string: "https://duckduckgo.com/subscriptions/welcome")!
        let testedURL = URL(string: "https://duckduckgo.com/subscriptions")!
        #expect(testedURL.isChild(of: parentURL) == false)
    }

    // Tests for URL normalization and canonicalization

    @Test("Normalizing URLs with spaces in different components")
    func normalizingURLsWithSpacesInDifferentComponents() throws {
        // Path with spaces
        let urlWithSpacesInPath = URL(string: "https://example.com/path with spaces/file.html")
        #expect(urlWithSpacesInPath?.absoluteString == "https://example.com/path%20with%20spaces/file.html")

        // Query with spaces
        let urlWithSpacesInQuery = URL(string: "https://example.com/search?q=test query&page=1")
        #expect(urlWithSpacesInQuery?.absoluteString == "https://example.com/search?q=test%20query&page=1")

        // Fragment with spaces
        let urlWithSpacesInFragment = URL(string: "https://example.com/page#section with spaces")
        #expect(urlWithSpacesInFragment?.absoluteString == "https://example.com/page#section%20with%20spaces")
    }

    @Test("Creating URLs with international characters")
    func creatingURLsWithInternationalCharacters() throws {
        // URL with international characters in domain
        let urlWithInternationalDomain = URL.makeURLUsingNativePredictionLogic(from: "https://例子.测试")
        #expect(urlWithInternationalDomain?.host == "xn--fsqu00a.xn--0zwm56d")
        #expect(urlWithInternationalDomain?.absoluteString == "https://xn--fsqu00a.xn--0zwm56d")

        // URL with international characters in path
        let urlWithInternationalPath = URL.makeURLUsingNativePredictionLogic(from: "https://example.com/пример/测试")
        #expect(urlWithInternationalPath?.absoluteString == "https://example.com/%D0%BF%D1%80%D0%B8%D0%BC%D0%B5%D1%80/%E6%B5%8B%E8%AF%95")
    }

    // Tests for URL manipulation methods

    @Test("Appending path components to a URL")
    func appendingPathToURL() throws {
        let baseURL = URL(string: "https://duckduckgo.com")!

        let urlWithAppendedPath = baseURL.appending("search")
        #expect(urlWithAppendedPath.absoluteString == "https://duckduckgo.com/search")

        let urlWithMultipleAppendedComponents = baseURL.appending("settings/privacy")
        #expect(urlWithMultipleAppendedComponents.absoluteString == "https://duckduckgo.com/settings/privacy")
    }

    @Test("Manipulating URL parameters")
    func manipulatingURLParameters() throws {
        let baseURL = URL(string: "https://duckduckgo.com/search")!

        // Append parameters
        let urlWithParameters = baseURL.appendingParameter(name: "q", value: "test query")
        #expect(urlWithParameters.absoluteString == "https://duckduckgo.com/search?q=test%20query")

        // Append multiple parameters
        let urlWithMultipleParams = urlWithParameters.appendingParameter(name: "t", value: "h_")
        #expect(urlWithMultipleParams.absoluteString == "https://duckduckgo.com/search?q=test%20query&t=h_")

        // Remove parameters
        if let urlWithRemovedParams = URL(string: "https://duckduckgo.com/search?q=test&t=h_&ia=web")?.removingParameters(named: ["t", "ia"]) {
            #expect(urlWithRemovedParams.absoluteString == "https://duckduckgo.com/search?q=test")
        }
    }

    // Tests for basic auth handling

    @Test("Extracting and removing basic auth credentials from URLs")
    func extractingAndRemovingBasicAuth() throws {
        let urlWithAuth = URL(string: "https://user name:pass%20word@example.com/secure")!

        // Extract credentials
        let credential = urlWithAuth.basicAuthCredential
        #expect(credential?.user == "user name")
        #expect(credential?.password == "pass word")

        // Remove credentials
        let urlWithoutAuth = urlWithAuth.removingBasicAuthCredential()
        #expect(urlWithoutAuth.absoluteString == "https://example.com/secure")
        #expect(urlWithoutAuth.basicAuthCredential == nil)
    }

    @Test("Matching URLs against protection spaces")
    func matchingURLsAgainstProtectionSpaces() throws {
        let url = URL(string: "https://example.com:8443/secure")!

        // Create protection space from URL
        let protectionSpace = try #require(url.basicAuthProtectionSpace)
        #expect(protectionSpace.host == "example.com")
        #expect(protectionSpace.port == 8443)
        #expect(protectionSpace.protocol == "https")

        // Match URL against protection space
        #expect(url.matches(protectionSpace) == true)

        // Different URL, same protection space
        let differentPathURL = URL(string: "https://example.com:8443/different")!
        #expect(differentPathURL.matches(protectionSpace) == true)

        // Different port
        let differentPortURL = URL(string: "https://example.com:9000/secure")!
        #expect(differentPortURL.matches(protectionSpace) == false)
    }

    // MARK: - Internal Page URL Tests

    @Test("Verifying internal page URL constants")
    func internalPageURLConstants() {
        #expect(URL.newtab.absoluteString == "duck://newtab")
        #expect(URL.settings.absoluteString == "duck://settings")
        #expect(URL.bookmarks.absoluteString == "duck://bookmarks")
        #expect(URL.history.absoluteString == "duck://history")
        #expect(URL.releaseNotes.absoluteString == "duck://release-notes")
        #expect(URL.dataBrokerProtection.absoluteString == "duck://personal-information-removal")
        #expect(URL.onboarding.absoluteString == "duck://onboarding")
        #expect(URL.blankPage.absoluteString == "about:blank")
    }

    @Test("Verifying invalid (legacy) URL constants")
    func invalidURLConstants() {
        #expect(URL.Invalid.aboutNewtab.absoluteString == "about:newtab")
        #expect(URL.Invalid.duckHome.absoluteString == "duck://home")
        #expect(URL.Invalid.aboutSettings.absoluteString == "about:settings")
        #expect(URL.Invalid.aboutPreferences.absoluteString == "about:preferences")
        #expect(URL.Invalid.aboutConfig.absoluteString == "about:config")
        #expect(URL.Invalid.duckConfig.absoluteString == "duck://config")
        #expect(URL.Invalid.duckPreferences.absoluteString == "duck://preferences")
        #expect(URL.Invalid.aboutHistory.absoluteString == "about:history")
        #expect(URL.Invalid.aboutBookmarks.absoluteString == "about:bookmarks")
    }

    // MARK: - Settings Pane URL Tests

    static let settingsPaneURLFormationArgs = [
        // Privacy Protection panes
        (PreferencePaneIdentifier.defaultBrowser, "duck://settings/defaultBrowser"),
        (.privateSearch, "duck://settings/privateSearch"),
        (.webTrackingProtection, "duck://settings/webTrackingProtection"),
        (.threatProtection, "duck://settings/threatProtection"),
        (.cookiePopupProtection, "duck://settings/cookiePopupProtection"),
        (.emailProtection, "duck://settings/emailProtection"),
        // Main Settings panes
        (.general, "duck://settings/general"),
        (.sync, "duck://settings/sync"),
        (.appearance, "duck://settings/appearance"),
        (.dataClearing, "duck://settings/dataClearing"),
        (.autofill, "duck://settings/autofill"),
        (.accessibility, "duck://settings/accessibility"),
        (.duckPlayer, "duck://settings/duckplayer"),
        (.aiChat, "duck://settings/aichat"),
        // Subscription panes
        (.subscription, "duck://settings/privacyPro"),
        (.vpn, "duck://settings/vpn"),
        (.personalInformationRemoval, "duck://settings/personalInformationRemoval"),
        (.paidAIChat, "duck://settings/paidAIChat"),
        (.identityTheftRestoration, "duck://settings/identityTheftRestoration"),
        (.subscriptionSettings, "duck://settings/subscriptionSettings"),
        // About
        (.about, "duck://settings/about")
    ]

    @Test("Creating settings pane URLs", arguments: settingsPaneURLFormationArgs)
    func settingsPaneURLFormation(pane: PreferencePaneIdentifier, expectedURL: String) {
        #expect(URL.settingsPane(pane).absoluteString == expectedURL)
    }

    static let settingsPaneURLParsingArgs = [
        // Standard duck://settings URLs (all panes)
        (URL.settingsPane(.defaultBrowser), PreferencePaneIdentifier.defaultBrowser as PreferencePaneIdentifier?),
        (URL.settingsPane(.privateSearch), .privateSearch as PreferencePaneIdentifier?),
        (URL.settingsPane(.webTrackingProtection), .webTrackingProtection as PreferencePaneIdentifier?),
        (URL.settingsPane(.threatProtection), .threatProtection as PreferencePaneIdentifier?),
        (URL.settingsPane(.cookiePopupProtection), .cookiePopupProtection as PreferencePaneIdentifier?),
        (URL.settingsPane(.emailProtection), .emailProtection as PreferencePaneIdentifier?),
        (URL.settingsPane(.general), .general as PreferencePaneIdentifier?),
        (URL.settingsPane(.sync), .sync as PreferencePaneIdentifier?),
        (URL.settingsPane(.appearance), .appearance as PreferencePaneIdentifier?),
        (URL.settingsPane(.dataClearing), .dataClearing as PreferencePaneIdentifier?),
        (URL.settingsPane(.autofill), .autofill as PreferencePaneIdentifier?),
        (URL.settingsPane(.accessibility), .accessibility as PreferencePaneIdentifier?),
        (URL.settingsPane(.duckPlayer), .duckPlayer as PreferencePaneIdentifier?),
        (URL.settingsPane(.aiChat), .aiChat as PreferencePaneIdentifier?),
        (URL.settingsPane(.subscription), .subscription as PreferencePaneIdentifier?),
        (URL.settingsPane(.vpn), .vpn as PreferencePaneIdentifier?),
        (URL.settingsPane(.personalInformationRemoval), .personalInformationRemoval as PreferencePaneIdentifier?),
        (URL.settingsPane(.paidAIChat), .paidAIChat as PreferencePaneIdentifier?),
        (URL.settingsPane(.identityTheftRestoration), .identityTheftRestoration as PreferencePaneIdentifier?),
        (URL.settingsPane(.subscriptionSettings), .subscriptionSettings as PreferencePaneIdentifier?),
        (URL.settingsPane(.about), .about as PreferencePaneIdentifier?),
        // Legacy URL formats
        (URL(string: "about:preferences/general")!, .general as PreferencePaneIdentifier?),
        (URL(string: "about:settings/appearance")!, .appearance as PreferencePaneIdentifier?),
        (URL(string: "about:config/sync")!, .sync as PreferencePaneIdentifier?),
        (URL(string: "duck://preferences/autofill")!, .autofill as PreferencePaneIdentifier?),
        (URL(string: "duck://config/dataClearing")!, .dataClearing as PreferencePaneIdentifier?),
        // Invalid URLs
        (URL(string: "https://example.com")!, nil as PreferencePaneIdentifier?),
        (URL.bookmarks, nil as PreferencePaneIdentifier?),
        (URL(string: "duck://settings/invalid-pane")!, nil as PreferencePaneIdentifier?)
    ]

    @Test("Parsing settings pane identifiers from URLs", arguments: settingsPaneURLParsingArgs)
    func settingsPaneURLParsing(url: URL, expectedPane: PreferencePaneIdentifier?) {
        #expect(PreferencePaneIdentifier(url: url) == expectedPane)
    }

    @Test("Validating settings URLs")
    func settingsURLValidation() {
        // Valid settings URLs
        #expect(URL.settings.isSettingsURL == true)
        #expect(URL.settingsPane(.general).isSettingsURL == true)
        #expect(URL.settingsPane(.appearance).isSettingsURL == true)

        // Invalid settings URLs
        #expect(URL.bookmarks.isSettingsURL == false)
        #expect(URL.history.isSettingsURL == false)
        #expect(URL(string: "https://duckduckgo.com")!.isSettingsURL == false)
    }

    // MARK: - History Pane URL Tests

    static let historyPaneURLFormationArgs = [
        (HistoryPaneIdentifier.all, "duck://history?range=all"),
        (.today, "duck://history?range=today"),
        (.yesterday, "duck://history?range=yesterday"),
        (.older, "duck://history?range=older"),
        (.sunday, "duck://history?range=sunday"),
        (.monday, "duck://history?range=monday"),
        (.tuesday, "duck://history?range=tuesday"),
        (.wednesday, "duck://history?range=wednesday"),
        (.thursday, "duck://history?range=thursday"),
        (.friday, "duck://history?range=friday"),
        (.saturday, "duck://history?range=saturday"),
        (.allSites, "duck://history?range=sites")
    ]

    @Test("Creating history pane URLs", arguments: historyPaneURLFormationArgs)
    func historyPaneURLFormation(range: HistoryPaneIdentifier, expectedURL: String) {
        #expect(URL.historyPane(range).absoluteString == expectedURL)
    }

    static let historyPaneURLParsingArgs = [
        // Valid duck://history URLs with path format
        (URL(string: "duck://history/all")!, HistoryPaneIdentifier.all as HistoryPaneIdentifier?),
        (URL(string: "duck://history/today")!, .today as HistoryPaneIdentifier?),
        (URL(string: "duck://history/yesterday")!, .yesterday as HistoryPaneIdentifier?),
        (URL(string: "duck://history/older")!, .older as HistoryPaneIdentifier?),
        (URL(string: "duck://history/sites")!, .allSites as HistoryPaneIdentifier?),
        (URL(string: "duck://history/sunday")!, .sunday as HistoryPaneIdentifier?),
        (URL(string: "duck://history/monday")!, .monday as HistoryPaneIdentifier?),
        (URL(string: "duck://history/tuesday")!, .tuesday as HistoryPaneIdentifier?),
        (URL(string: "duck://history/wednesday")!, .wednesday as HistoryPaneIdentifier?),
        (URL(string: "duck://history/thursday")!, .thursday as HistoryPaneIdentifier?),
        (URL(string: "duck://history/friday")!, .friday as HistoryPaneIdentifier?),
        (URL(string: "duck://history/saturday")!, .saturday as HistoryPaneIdentifier?),
        // Legacy about:history URLs
        (URL(string: "about:history/all")!, .all as HistoryPaneIdentifier?),
        (URL(string: "about:history/today")!, .today as HistoryPaneIdentifier?),
        (URL(string: "about:history/yesterday")!, .yesterday as HistoryPaneIdentifier?),
        (URL(string: "about:history/older")!, .older as HistoryPaneIdentifier?),
        (URL(string: "about:history/sites")!, .allSites as HistoryPaneIdentifier?),
        // Invalid URLs
        (URL.history, nil as HistoryPaneIdentifier?),
        (URL.bookmarks, nil as HistoryPaneIdentifier?),
        (URL(string: "https://example.com")!, nil as HistoryPaneIdentifier?),
        (URL(string: "duck://history/invalid")!, nil as HistoryPaneIdentifier?)
    ]

    @Test("Parsing history pane identifiers from URLs", arguments: historyPaneURLParsingArgs)
    func historyPaneURLParsing(url: URL, expectedRange: HistoryPaneIdentifier?) {
        #expect(HistoryPaneIdentifier(url: url) == expectedRange)
    }

    @Test("Validating history URLs")
    func historyURLValidation() {
        // Valid history URLs
        #expect(URL.history.isHistory == true)
        #expect(URL(string: "duck://history/today")!.isHistory == true)

        // Invalid history URLs
        #expect(URL.bookmarks.isHistory == false)
        #expect(URL.settings.isHistory == false)
        #expect(URL(string: "https://duckduckgo.com")!.isHistory == false)
    }

    // MARK: - TabContent Creation Tests

    @Test("Creating TabContent from newtab URLs")
    func tabContentFromNewtabURLs() {
        #expect(TabContent.contentFromURL(.newtab, source: .ui) == .newtab)
        #expect(TabContent.contentFromURL(.Invalid.aboutNewtab, source: .ui) == .newtab)
        #expect(TabContent.contentFromURL(.Invalid.duckHome, source: .ui) == .newtab)
    }

    static let tabContentFromSettingsURLsArgs = [
        // Base settings URL
        (URL.settings, TabContent.anySettingsPane),
        // Legacy settings URLs
        (URL.Invalid.aboutPreferences, TabContent.anySettingsPane),
        (URL.Invalid.aboutConfig, TabContent.anySettingsPane),
        (URL.Invalid.aboutSettings, TabContent.anySettingsPane),
        (URL.Invalid.duckConfig, TabContent.anySettingsPane),
        (URL.Invalid.duckPreferences, TabContent.anySettingsPane),
        // Settings with specific panes
        (URL.settingsPane(.general), TabContent.settings(pane: .general)),
        (URL.settingsPane(.appearance), TabContent.settings(pane: .appearance)),
        (URL.settingsPane(.sync), TabContent.settings(pane: .sync)),
        (URL.settingsPane(.autofill), TabContent.settings(pane: .autofill)),
        (URL.settingsPane(.dataClearing), TabContent.settings(pane: .dataClearing)),
        (URL.settingsPane(.accessibility), TabContent.settings(pane: .accessibility))
    ]

    @Test("Creating TabContent from settings URLs", arguments: tabContentFromSettingsURLsArgs)
    func tabContentFromSettingsURLs(url: URL, expectedContent: TabContent) {
        #expect(TabContent.contentFromURL(url, source: .ui) == expectedContent)
    }

    @Test("Creating TabContent from bookmarks URLs")
    func tabContentFromBookmarksURLs() {
        #expect(TabContent.contentFromURL(.bookmarks, source: .ui) == .bookmarks)
        #expect(TabContent.contentFromURL(.Invalid.aboutBookmarks, source: .ui) == .bookmarks)
    }

    static let tabContentFromHistoryURLsArgs = [
        // Base history URLs
        (URL.history, TabContent.anyHistoryPane),
        (URL.Invalid.aboutHistory, TabContent.anyHistoryPane),
        // History with specific panes
        (URL(string: "duck://history/all")!, TabContent.history(pane: .all)),
        (URL(string: "duck://history/today")!, TabContent.history(pane: .today)),
        (URL(string: "duck://history/yesterday")!, TabContent.history(pane: .yesterday)),
        (URL(string: "duck://history/older")!, TabContent.history(pane: .older)),
        (URL(string: "duck://history/sites")!, TabContent.history(pane: .allSites)),
        // Legacy about:history with panes
        (URL(string: "about:history/today")!, TabContent.history(pane: .today))
    ]

    @Test("Creating TabContent from history URLs", arguments: tabContentFromHistoryURLsArgs)
    func tabContentFromHistoryURLs(url: URL, expectedContent: TabContent) {
        #expect(TabContent.contentFromURL(url, source: .ui) == expectedContent)
    }

    @Test("Creating TabContent from other internal page URLs")
    func tabContentFromOtherInternalPages() {
        #expect(TabContent.contentFromURL(.onboarding, source: .ui) == .onboarding)
        #expect(TabContent.contentFromURL(.dataBrokerProtection, source: .ui) == .dataBrokerProtection)
        #expect(TabContent.contentFromURL(.releaseNotes, source: .ui) == .releaseNotes)
    }

    @Test("Creating TabContent from external URLs")
    func tabContentFromExternalURLs() {
        let externalURL = URL(string: "https://duckduckgo.com")!
        let tabContent = TabContent.contentFromURL(externalURL, source: .userEntered("https://duckduckgo.com", downloadRequested: false))

        if case .url(let url, _, _) = tabContent {
            #expect(url == externalURL)
        } else {
            Issue.record("Expected .url case")
        }
    }

    static let tabContentURLForWebViewArgs = [
        // Base internal pages
        (TabContent.newtab, URL.newtab),
        (TabContent.bookmarks, URL.bookmarks),
        (TabContent.anyHistoryPane, URL.history),
        (TabContent.anySettingsPane, URL.settings),
        (TabContent.onboarding, URL.onboarding),
        (TabContent.dataBrokerProtection, URL.dataBrokerProtection),
        (TabContent.releaseNotes, URL.releaseNotes),
        // Settings with panes
        (TabContent.settings(pane: .general), URL.settingsPane(.general)),
        (TabContent.settings(pane: .appearance), URL.settingsPane(.appearance)),
        (TabContent.settings(pane: .sync), URL.settingsPane(.sync)),
        // History with panes (uses query parameter format, parser now accepts both formats)
        (TabContent.history(pane: .today), URL.historyPane(.today)),
        (TabContent.history(pane: .all), URL.historyPane(.all)),
        (TabContent.history(pane: .yesterday), URL.historyPane(.yesterday))
    ]

    @Test("TabContent urlForWebView returns correct URLs", arguments: tabContentURLForWebViewArgs)
    func tabContentURLForWebView(content: TabContent, expectedURL: URL) {
        #expect(content.urlForWebView == expectedURL)
    }

    // MARK: - Round-trip Tests: URL formation → TabContent → URL validation

    static let settingsPaneRoundTripArgs: [PreferencePaneIdentifier] = [
        // Privacy Protection panes
        .defaultBrowser, .privateSearch, .webTrackingProtection, .threatProtection,
        .cookiePopupProtection, .emailProtection,
        // Main Settings panes
        .general, .sync, .appearance, .dataClearing, .autofill, .accessibility,
        .duckPlayer, .aiChat,
        // Subscription panes
        .subscription, .vpn, .personalInformationRemoval, .paidAIChat,
        .identityTheftRestoration, .subscriptionSettings,
        // About
        .about
        // Note: .otherPlatforms is excluded - it's a special case with an HTTPS URL as rawValue
        // that opens in a new tab rather than creating a duck://settings/ URL
    ]

    @Test("Settings pane URLs should be parseable back to PreferencePaneIdentifier",
          arguments: settingsPaneRoundTripArgs)
    func settingsPaneURLShouldBeParseable(pane: PreferencePaneIdentifier) {
        // Given: URL created using URL.settingsPane()
        let url = URL.settingsPane(pane)

        // When: Parsing the URL back to PreferencePaneIdentifier
        let parsed = PreferencePaneIdentifier(url: url)

        // Then: Should successfully parse back to the original pane
        #expect(parsed == pane)
    }

    @Test("Settings pane round-trip: URL.settingsPane() → TabContent → urlForWebView", arguments: settingsPaneRoundTripArgs)
    func settingsPaneRoundTrip(pane: PreferencePaneIdentifier) {
        // Step 1: Form URL using URL extension method
        let formedURL = URL.settingsPane(pane)

        // Step 2: Create TabContent from the formed URL
        let tabContent = TabContent.contentFromURL(formedURL, source: .ui)

        // Step 3: Validate TabContent matches expected pane
        #expect(tabContent == .settings(pane: pane))

        // Step 4: Validate URL from TabContent matches original formed URL
        #expect(tabContent.urlForWebView == formedURL)
    }

    static let historyPaneRoundTripArgs: [HistoryPaneIdentifier] = [
        // Time-based ranges
        .all, .today, .yesterday, .older,
        // Weekday ranges
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
        // Sites view
        .allSites
    ]

    @Test("History pane round-trip: path URL → TabContent → query URL (asymmetric)", arguments: historyPaneRoundTripArgs)
    func historyPaneRoundTrip(range: HistoryPaneIdentifier) {
        // Note: History has asymmetric URL format
        // Parsing accepts path-based: duck://history/today
        // Formation generates query-based: duck://history?range=today

        // Step 1: Create path-based URL for parsing (simulating user navigation)
        let pathURL = URL(string: "duck://history/\(range.rawValue)")!

        // Step 2: Create TabContent from path-based URL
        let tabContent = TabContent.contentFromURL(pathURL, source: .ui)

        // Step 3: Validate TabContent matches expected range
        #expect(tabContent == .history(pane: range))

        // Step 4: Validate URL from TabContent uses query-based format
        let expectedQueryURL = URL.historyPane(range)
        #expect(tabContent.urlForWebView == expectedQueryURL)
        #expect(tabContent.urlForWebView?.absoluteString.contains("?range=") == true)
    }

    static let internalPageRoundTripArgs = [
        (URL.bookmarks, TabContent.bookmarks),
        (URL.newtab, TabContent.newtab),
        (URL.onboarding, TabContent.onboarding),
        (URL.dataBrokerProtection, TabContent.dataBrokerProtection),
        (URL.releaseNotes, TabContent.releaseNotes)
    ]

    @Test("Internal page round-trip: URL constant → TabContent → urlForWebView", arguments: internalPageRoundTripArgs)
    func internalPageRoundTrip(url: URL, expectedContent: TabContent) {
        // Step 1: URL is already formed (internal page constant)

        // Step 2: Create TabContent from URL
        let tabContent = TabContent.contentFromURL(url, source: .ui)

        // Step 3: Validate TabContent matches expected
        #expect(tabContent == expectedContent)

        // Step 4: Validate URL from TabContent matches original
        #expect(tabContent.urlForWebView == url)
    }

    @Test("Special case: otherPlatforms creates HTTPS URL, not settings URL")
    func otherPlatformsSpecialCase() {
        // otherPlatforms is unique - its rawValue is a full HTTPS URL
        // It's designed to open in a new tab, not create a duck://settings/ URL
        let otherPlatformsRawValue = PreferencePaneIdentifier.otherPlatforms.rawValue

        // Verify it's an HTTPS URL
        #expect(otherPlatformsRawValue.hasPrefix("https://"))
        #expect(otherPlatformsRawValue == "https://duckduckgo.com/app/devices?origin=funnel_app_macos")

        // URL.settingsPane(.otherPlatforms) would create an invalid URL like:
        // "duck://settings/https://duckduckgo.com/app/devices?origin=funnel_app_macos"
        // This is by design - otherPlatforms is handled specially in the UI
        let settingsURL = URL.settingsPane(.otherPlatforms)
        #expect(settingsURL.absoluteString.contains("duck://settings/https://"))

        // The pane opens an external URL directly, not through settings URL scheme
        let externalURL = URL(string: otherPlatformsRawValue)
        #expect(externalURL != nil)
        #expect(externalURL?.scheme == "https")
    }

    // MARK: - History Pane Round-Trip Parsing Tests

    @Test("History pane URLs should be parseable back to HistoryPaneIdentifier",
          arguments: historyPaneRoundTripArgs)
    func historyPaneURLShouldBeParseable(range: HistoryPaneIdentifier) {
        // Given: URL created using URL.historyPane() with query parameter format
        let url = URL.historyPane(range)

        // When: Parsing the URL back to HistoryPaneIdentifier
        let parsed = HistoryPaneIdentifier(url: url)

        // Then: Should successfully parse back to the original range
        // Parser now accepts both query (?range=) and path (/today) formats
        #expect(parsed == range)
    }

    @Test("History pane parser accepts both query and path formats",
          arguments: historyPaneRoundTripArgs)
    func historyPaneParserAcceptsBothFormats(range: HistoryPaneIdentifier) {
        // Query parameter format (new format used by URL.historyPane())
        let queryURL = URL(string: "duck://history?range=\(range.rawValue)")!
        let parsedFromQuery = HistoryPaneIdentifier(url: queryURL)
        #expect(parsedFromQuery == range, "Query format should parse correctly")

        // Path format (legacy format for backwards compatibility)
        let pathURL = URL(string: "duck://history/\(range.rawValue)")!
        let parsedFromPath = HistoryPaneIdentifier(url: pathURL)
        #expect(parsedFromPath == range, "Path format should still parse for backwards compatibility")
    }

}

extension URLExtensionTests {
    struct Case {
        let string: String
        let expectation: String?
        let line: Int

        var sourceLocation: SourceLocation {
            SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1)
        }

        init(_ string: String, _ expectation: String?, line: Int = #line) {
            self.string = string
            self.expectation = expectation
            self.line = line
        }
    }
}
