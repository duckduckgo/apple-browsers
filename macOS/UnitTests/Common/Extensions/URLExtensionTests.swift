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
