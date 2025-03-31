//
//  URLExtensionTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation
import Testing

@testable import Common

final class URLExtensionTests {

    @Test("External URLs are valid")
    func external_urls_are_valid() {
        #expect("mailto://user@host.tld".url!.isValid)
        #expect("sms://+44776424232323".url!.isValid)
        #expect("ftp://example.com".url!.isValid)
    }

    static let navigational_urls_args: [(String, UInt)] = [
        ("http://example.com", #line),
        ("https://example.com", #line),
        ("http://localhost", #line),
        ("http://localdomain", #line),
        ("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment", #line),
        ("user@somehost.local:9091/index.html", #line),
        ("user:@something.local:9100", #line),
        ("user:%20@localhost:5000", #line),
        ("user:passwOrd@localhost:5000", #line),
        ("user%40local:pa%24%24s@localhost:5000", #line),
        ("mailto:test@example.com", #line),
        ("192.168.1.1", #line),
        ("http://192.168.1.1", #line),
        ("http://sheep%2B:P%40%24swrd@192.168.1.1", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1/", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1:8900/", #line),
        ("sheep%2B:P%40%24swrd@💩.la?arg=b#1", #line),
        ("sheep%2B:P%40%24swrd@xn--ls8h.la/?arg=b#1", #line),
        ("https://sheep%2B:P%40%24swrd@💩.la", #line),
        ("data:text/vnd-example+xyz;foo=bar;base64,R0lGODdh", #line),
        ("http://192.168.0.1", #line),
        ("http://203.0.113.0", #line),
        ("http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]", #line),
        ("http://[2001:0db8::1]", #line),
        ("http://[::]:8080", #line),
        ("https://www.duckduckgo.com/html?q =search", #line),
    ]

    @Test("Navigational URLs are valid", arguments: navigational_urls_args)
    func navigational_urls_are_valid(rawValue: String, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let url = rawValue.decodedURL
        #expect(url != nil, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        #expect(url!.isValid, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
    }

    static let non_valid_urls_args = [
        "about:user:pass@blank",
        "data:user:pass@text/vnd-example+xyz;foo=bar;base64,R0lGODdh",
    ]

    @Test("Non-valid URLs")
    func non_valid_urls() throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        for item in Self.non_valid_urls_args {
            #expect(item.url == nil)
        }
    }

    @Test("URL scheme is added when missing")
    func when_no_scheme_in_string_url_has_scheme() {
        #expect("duckduckgo.com".url!.absoluteString == "http://duckduckgo.com")
        #expect("example.com".url!.absoluteString == "http://example.com")
        #expect("localhost".url!.absoluteString == "http://localhost")
        #expect("localdomain".url == nil)
    }

    @Test("IPv4 addresses must contain four octets")
    func ipv4AddressMustContainFourOctets() {
        #expect("1.4".url == nil)
        #expect("1.4/3.4".url == nil)
        #expect("1.0.4".url == nil)
        #expect("127.0.1".url == nil)

        #expect("127.0.0.1".url?.absoluteString == "http://127.0.0.1")
        #expect("1.0.0.4/3.4".url?.absoluteString == "http://1.0.0.4/3.4")
    }

    @Test("URL.naked returns a normalized URL without scheme, www prefix, and trailing slash")
    func nakedIsCalled_returnsURLWithNoSchemeWWWPrefixAndLastSlash() {
        let url = URL(string: "http://duckduckgo.com")!
        let duplicate = URL(string: "https://www.duckduckgo.com/")!

        #expect(url.naked == duplicate.naked)
    }

    @Test("URL.root returns a URL with the host only, removing all other components")
    func rootIsCalled_returnsURLWithNoPathQueryFragmentUserAndPassword() {
        let url = URL(string: "https://dax:123456@www.duckduckgo.com/test.php?test=S&info=test#fragment")!

        let rootUrl = url.root!
        #expect(rootUrl == URL(string: "https://www.duckduckgo.com/")!)
        #expect(rootUrl.isRoot)
    }

    static let basicAuthCredential_args: [(String, String?, String?, UInt)] = [
        ("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment", "dax@duck.com", "123:456A", #line),
        ("user@somehost.local:9091/index.html", "user", "", #line),
        ("user:@something.local:9100", "user", "", #line),
        ("user:%20@localhost:5000", "user", " ", #line),
        ("user:passwOrd@localhost:5000", "user", "passwOrd", #line),
        ("user%40local:pa%24%24@localhost:5000", "user@local", "pa$$", #line),
        ("mailto:test@example.com", nil, nil, #line),
        ("sheep%2B:P%40%24swrd@💩.la", "sheep+", "P@$swrd", #line),
        ("sheep%2B:P%40%24swrd@xn--ls8h.la/", "sheep+", "P@$swrd", #line),
        ("https://sheep%2B:P%40%24swrd@💩.la", "sheep+", "P@$swrd", #line),
        ("http://sheep%2B:P%40%24swrd@192.168.1.1", "sheep+", "P@$swrd", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1", "sheep+", "P@$swrd", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1/", "sheep+", "P@$swrd", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1:8900/", "sheep+", "P@$swrd", #line),
    ]

    @Test("Basic auth credentials are correctly extracted from URLs", arguments: basicAuthCredential_args)
    func basicAuthCredential(url: String, user: String?, password: String?, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let credential = url.decodedURL!.basicAuthCredential
        #expect(credential?.user == user, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        #expect(credential?.password == password, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
    }

    static let urlRemovingBasicAuthCredential_args: [(String, String, UInt)] = [
        ("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment", "https://www.duckduckgo.com/test.php?test=S&info=test#fragment", #line),
        ("user@somehost.local:9091/index.html", "http://somehost.local:9091/index.html", #line),
        ("user:@something.local:9100", "http://something.local:9100", #line),
        ("user:%20@localhost:5000", "http://localhost:5000", #line),
        ("user:passwOrd@localhost:5000", "http://localhost:5000", #line),
        ("user%40local:pa%24%24s@localhost:5000", "http://localhost:5000", #line),
        ("mailto:test@example.com", "mailto:test@example.com", #line),
        ("sheep%2B:P%40%24swrd@💩.la", "http://xn--ls8h.la", #line),
        ("sheep%2B:P%40%24swrd@xn--ls8h.la/", "http://xn--ls8h.la/", #line),
        ("https://sheep%2B:P%40%24swrd@💩.la", "https://xn--ls8h.la", #line),
        ("http://sheep%2B:P%40%24swrd@192.168.1.1", "http://192.168.1.1", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1", "http://192.168.1.1", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1/", "http://192.168.1.1/", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1:8900", "http://192.168.1.1:8900", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1:8900/", "http://192.168.1.1:8900/", #line),
    ]

    @Test("Basic auth credentials are correctly removed from URLs", arguments: urlRemovingBasicAuthCredential_args)
    func urlRemovingBasicAuthCredential(url: String, removingCredential: String, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let filtered = url.decodedURL!.removingBasicAuthCredential()
        #expect(filtered.absoluteString == removingCredential, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
    }

    @Test("URL.isRoot correctly identifies root URLs")
    func isRoot() {
        let url = URL(string: "https://www.server.com:8080/path?query=string#fragment")!
        let rootUrl = URL(string: "https://www.server.com:8080/")!

        #expect(rootUrl.isRoot)
        #expect(!url.isRoot)
    }

    @Test("URL.appendingParameter doesn't change the original URL")
    func addParameterIsCalled_doesNotChangeExistingURL() {
        let url = URL(string: "https://duckduckgo.com/?q=Battle%20star+Galactica%25a")!

        #expect(
            url.appendingParameter(name: "ia", value: "web") ==
            URL(string: "https://duckduckgo.com/?q=Battle%20star+Galactica%25a&ia=web")!
        )
    }

    static let rfc3986QueryReservedChars_args: [(String, String, String, UInt)] = [
        (":", ":", "https://duck.com/?%3A=%3A", #line),
        ("/", "/", "https://duck.com/?%2F=%2F", #line),
        ("?", "?", "https://duck.com/?%3F=%3F", #line),
        ("#", "#", "https://duck.com/?%23=%23", #line),
        ("[", "[", "https://duck.com/?%5B=%5B", #line),
        ("]", "]", "https://duck.com/?%5D=%5D", #line),
        ("@", "@", "https://duck.com/?%40=%40", #line),
        ("!", "!", "https://duck.com/?%21=%21", #line),
        ("$", "$", "https://duck.com/?%24=%24", #line),
        ("&", "&", "https://duck.com/?%26=%26", #line),
        ("'", "'", "https://duck.com/?%27=%27", #line),
        ("(", "(", "https://duck.com/?%28=%28", #line),
        (")", ")", "https://duck.com/?%29=%29", #line),
        ("*", "*", "https://duck.com/?%2A=%2A", #line),
        ("+", "+", "https://duck.com/?%2B=%2B", #line),
        (",", ",", "https://duck.com/?%2C=%2C", #line),
        (";", ";", "https://duck.com/?%3B=%3B", #line),
        ("=", "=", "https://duck.com/?%3D=%3D", #line),
    ]

    @Test("URL.appendingParameter correctly encodes RFC3986 reserved characters", arguments: rfc3986QueryReservedChars_args)
    func addParameterIsCalled_encodesRFC3986QueryReservedCharactersInTheParameter(name: String, value: String, expected: String, line: UInt) {
        let url = URL(string: "https://duck.com/")!
        #expect(url.appendingParameter(name: name, value: value).absoluteString == expected, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
    }

    @Test("URL.appendingParameter allows unescaped reserved characters when specified")
    func addParameterIsCalled_allowsUnescapedReservedCharactersAsSpecified() {
        let url = URL(string: "https://duck.com/")!

        #expect(
            url.appendingParameter(
                name: "domains",
                value: "test.com,example.com/test,localhost:8000/api",
                allowedReservedCharacters: .init(charactersIn: ",:")
            ).absoluteString ==
            "https://duck.com/?domains=test.com,example.com%2Ftest,localhost:8000%2Fapi"
        )
    }

    @Test("URL.trimmedAddressBarString returns nil for empty input")
    func punycodeUrlIsCalledOnEmptyStringReturnsNil() {
        #expect(URL(trimmedAddressBarString: "")?.absoluteString == nil)
    }

    @Test("URL.trimmedAddressBarString returns nil for space input")
    func punycodeUrlIsCalledOnQueryReturnsNil() {
        #expect(URL(trimmedAddressBarString: " ")?.absoluteString == nil)
    }

    @Test("URL.trimmedAddressBarString returns nil for URLs with spaces in the hostname")
    func punycodeUrlIsCalledOnQueryWithSpaceThenUrlIsNotReturned() {
        #expect(URL(trimmedAddressBarString: "https://www.duckduckgo .com/html?q=search")?.absoluteString == nil)
    }

    @Test("URL.trimmedAddressBarString returns nil for unicode local hostnames")
    func punycodeUrlIsCalledOnLocalHostnameReturnsNil() {
        #expect(URL(trimmedAddressBarString: "💩")?.absoluteString == nil)
    }

    @Test("URL.trimmedAddressBarString doesn't interpret 'define:' as a local URL")
    func defineSearchRequestIsMadeNotInterpretedAsLocalURL() {
        #expect(URL(trimmedAddressBarString: "define:300/spartans")?.absoluteString == nil)
    }

    static let addressBarURLParsing_args: [(String, String?, UInt)] = [
        ("user@somehost.local:9091/index.html", nil, #line),
        ("something.local:9100", nil, #line),
        ("user@localhost:5000", nil, #line),
        ("user:password@localhost:5000", nil, #line),
        ("localhost", nil, #line),
        ("localhost:5000", nil, #line),
        ("sms://+44123123123", nil, #line),
        ("mailto:test@example.com", nil, #line),
        ("mailto:u%24ser@💩.la?arg=b#1", "mailto:u%24ser@xn--ls8h.la?arg=b%231", #line),
        ("62.12.14.111", nil, #line),
        ("https://", nil, #line),
        ("http://duckduckgo.com", nil, #line),
        ("https://duckduckgo.com", nil, #line),
        ("https://duckduckgo.com/", nil, #line),
        ("duckduckgo.com", nil, #line),
        ("duckduckgo.com/html?q=search", nil, #line),
        ("www.duckduckgo.com", nil, #line),
        ("https://www.duckduckgo.com/html?q=search", nil, #line),
        ("https://www.duckduckgo.com/html/?q=search", nil, #line),
        ("ftp://www.duckduckgo.com", nil, #line),
        ("file:///users/user/Documents/afile", nil, #line),
        ("https://www.duckduckgo.com/html?q =search", "https://www.duckduckgo.com/html?q%20=search", #line),
    ]

    @Test("URL.trimmedAddressBarString correctly parses various address bar inputs", arguments: addressBarURLParsing_args)
    func addressBarURLParsing(address: String, expectation: String? = nil, line: UInt) {
        let url = URL(trimmedAddressBarString: address)
        var expectedString = expectation ?? address
        let expectedScheme = address.hasPrefix("mailto:") ? "mailto" : (address.split(separator: "/").first.flatMap {
            $0.hasSuffix(":") ? String($0).dropping(suffix: ":") : nil
        }?.lowercased() ?? "http")
        if !address.hasPrefix(expectedScheme) {
            expectedString = expectedScheme + "://" + address
        }
        #expect(url?.scheme == expectedScheme, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        #expect(url?.absoluteString == expectedString, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
    }

    @Test("URL.trimmedAddressBarString escapes invalid characters in URL parameters")
    func urlParametersModifiedWithInvalidCharactersThenParametersArePercentEscaped() {
        #expect(URL(trimmedAddressBarString: "https://www.duckduckgo.com/html?q=a%20search with+space?+and%25plus&ia=calculator")!.absoluteString ==
                "https://www.duckduckgo.com/html?q=a%20search%20with+space?+and%25plus&ia=calculator")
    }

    @Test("URL.trimmedAddressBarString preserves empty query markers")
    func urlWithEmptyQueryIsFixedUpQuestionCharIsKept() {
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/?")!.absoluteString ==
               "https://duckduckgo.com/?")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com?")!.absoluteString ==
               "https://duckduckgo.com?")
        #expect(URL(trimmedAddressBarString: "https:/duckduckgo.com/?")!.absoluteString ==
               "https://duckduckgo.com/?")
        #expect(URL(trimmedAddressBarString: "https:/duckduckgo.com?")!.absoluteString ==
               "https://duckduckgo.com?")
    }

    @Test("URL.trimmedAddressBarString escapes hash fragments correctly")
    func urlWithHashIsFixedUpHashIsCorrectlyEscaped() {
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/#hash with #")!.absoluteString ==
               "https://duckduckgo.com/#hash%20with%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q=a b#hash with #")!.absoluteString ==
               "https://duckduckgo.com/html?q=a%20b#hash%20with%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html#hash with #")!.absoluteString ==
               "https://duckduckgo.com/html#hash%20with%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q#hash with #")!.absoluteString ==
               "https://duckduckgo.com/html?q#hash%20with%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html?#hash with? #")!.absoluteString ==
               "https://duckduckgo.com/html?#hash%20with?%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q=a b#")!.absoluteString ==
               "https://duckduckgo.com/html?q=a%20b#")
    }

    static let punycodeUrls_args: [(String, String, UInt)] = [
        ("💩.la", "http://xn--ls8h.la", #line),
        ("💩.la/", "http://xn--ls8h.la/", #line),
        ("82.мвд.рф", "http://82.xn--b1aew.xn--p1ai", #line),
        ("http://💩.la:8080", "http://xn--ls8h.la:8080", #line),
        ("http://💩.la", "http://xn--ls8h.la", #line),
        ("https://💩.la", "https://xn--ls8h.la", #line),
        ("https://💩.la/", "https://xn--ls8h.la/", #line),
        ("https://💩.la/path/to/resource", "https://xn--ls8h.la/path/to/resource", #line),
        ("https://💩.la/path/to/resource?query=true", "https://xn--ls8h.la/path/to/resource?query=true", #line),
        ("https://💩.la/💩", "https://xn--ls8h.la/%F0%9F%92%A9", #line),
    ]

    @Test("URL.trimmedAddressBarString correctly handles punycode URLs", arguments: punycodeUrls_args)
    func punycodeUrlIsCalledWithEncodedUrlsReturnsCorrectURL(input: String, expected: String, line: UInt) {
        #expect(input.decodedURL?.absoluteString == expected, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
    }

    @Test("URL.getParameter returns the correct value when the parameter exists")
    func paramExistsThengetParameterReturnsCorrectValue() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let expected = "secondValue"
        let actual = url.getParameter(named: "secondParam")
        #expect(actual == expected)
    }

    @Test("URL.getParameter returns nil when the parameter doesn't exist")
    func paramDoesNotExistThengetParameterIsNil() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let result = url.getParameter(named: "someOtherParam")
        #expect(result == nil)
    }

    @Test("URL.removeParameter returns a URL without the specified parameter")
    func paramExistsThenRemovingReturnUrlWithoutParam() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let expected = URL(string: "http://test.com?secondParam=secondValue")!
        let actual = url.removeParameter(name: "firstParam")
        #expect(actual == expected)
    }

    @Test("URL.removeParameter returns the same URL when the parameter doesn't exist")
    func paramDoesNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removeParameter(name: "someOtherParam")
        #expect(actual == url)
    }

    @Test("URL.removeParameter preserves plus signs in remaining parameters")
    func removingAParamThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")!
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")!
        let actual = url.removeParameter(name: "firstParam")
        #expect(actual == expected)
    }

    @Test("URL.removingParameters returns a URL without the specified parameters")
    func removingParamsThenRemovingReturnsUrlWithoutParams() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue&thirdParam=thirdValue")!
        let expected = URL(string: "http://test.com?secondParam=secondValue")!
        let actual = url.removingParameters(named: ["firstParam", "thirdParam"])
        #expect(actual == expected)
    }

    @Test("URL.removingParameters returns the same URL when no parameters match")
    func paramsDoNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removingParameters(named: ["someParam", "someOtherParam"])
        #expect(actual == url)
    }

    @Test("URL.removingParameters returns the same URL when given an empty array")
    func emptyParamArrayIsUsedThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removingParameters(named: [])
        #expect(actual == url)
    }

    @Test("URL.removingParameters preserves plus signs in remaining parameters")
    func removingParamsThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")!
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")!
        let actual = url.removingParameters(named: ["firstParam"])
        #expect(actual == expected)
    }

    @Test("URL.appendingParameter adds a query string when there are no parameters")
    func noParamsThenAddingAppendsQuery() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=aValue")!
        let actual = url.appendingParameter(name: "aParam", value: "aValue")
        #expect(actual == expected)
    }

    @Test("URL.appendingParameter appends to existing query parameters")
    func paramDoesNotExistThenAddingParamAppendsItToExistingQuery() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&anotherParam=anotherValue")!
        let actual = url.appendingParameter(name: "anotherParam", value: "anotherValue")
        #expect(actual == expected)
    }

    @Test("URL.appendingParameter encodes parameters with invalid characters")
    func paramHasInvalidCharactersThenAddingParamAppendsEncodedVersion() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=43%20%2B%205")!
        let actual = url.appendingParameter(name: "aParam", value: "43 + 5")
        #expect(actual == expected)
    }

    @Test("URL.appendingParameter adds a new value for an existing parameter")
    func paramExistsThenAddingNewValueAppendsParam() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&firstParam=newValue")!
        let actual = url.appendingParameter(name: "firstParam", value: "newValue")
        #expect(actual == expected)
    }

    static let matches_comparator_args: [(String, String, Bool, UInt)] = [
        ("youtube.com", "http://youtube.com", true, #line),
        ("youtube.com/", "http://youtube.com", true, #line),
        ("youtube.com", "http://youtube.com/", true, #line),
        ("youtube.com/", "http://youtube.com/", true, #line),
        ("http://youtube.com/", "youtube.com", true, #line),
        ("http://youtube.com", "youtube.com/", true, #line),
        ("https://youtube.com/", "https://youtube.com", true, #line),
        ("https://youtube.com/#link#1", "https://youtube.com#link#1", true, #line),
        ("https://youtube.com/#link#1", "https://youtube.com#link#1", true, #line),
        ("https://youtube.com/#link#1", "https://youtube.com/#link#1", true, #line),
        ("https://youtube.com#link#1", "https://youtube.com/#link#1", true, #line),

        ("youtube.com", "https://youtube.com", false, #line),
        ("youtube.com/", "https://youtube.com", false, #line),
        ("youtube.com/#link#1", "https://youtube.com#link#2", false, #line),
        ("youtube.com/#link#1", "https://youtube.com#link", false, #line),
    ]

    @Test("URL.matches correctly compares URLs", arguments: matches_comparator_args)
    func matchesComparator(url1: String, url2: String, expected: Bool, line: UInt) {
        if expected {
            #expect(url1.url!.matches(url2.url!), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        } else {
            #expect(!url1.url!.matches(url2.url!), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        }
    }

    static let matches_protection_space_args: [(String, String, Int, String, Bool, UInt)] = [
        ("youtube.com", "youtube.com", 80, "http", true, #line),
        ("http://youtube.com", "youtube.com", 80, "http", true, #line),
        ("https://youtube.com:123", "youtube.com", 123, "https", true, #line),

        ("https://youtube.com:123", "youtube.com", 1234, "https", false, #line),
        ("https://youtube.com:123", "youtube.com", 123, "http", false, #line),
        ("https://www.youtube.com:123", "youtube.com", 123, "https", false, #line),
    ]

    @Test("URL.matches correctly matches against protection spaces", arguments: matches_protection_space_args)
    func matchesProtectionSpace(url: String, host: String, port: Int, scheme: String, expected: Bool, line: UInt) {
        let protectionSpace = URLProtectionSpace(host: host, port: port, protocol: scheme, realm: "realm", authenticationMethod: "basic")
        if expected {
            #expect(url.url!.matches(protectionSpace), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        } else {
            #expect(!url.url!.matches(protectionSpace), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        }
    }

    @Test("URL.getQueryItem returns the correct query item when it exists")
    func queryItemWithNameAndURLHasQueryItemReturnsQueryItem() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com?origin=test"))

        // WHEN
        let result = url.getQueryItem(named: "origin")

        // THEN
        let queryItem = try #require(result)
        #expect(queryItem.name == "origin")
        #expect(queryItem.value == "test")
    }

    @Test("URL.getQueryItem returns nil when the query item doesn't exist")
    func queryItemWithNameAndURLDoesNotHaveQueryItemReturnsNil() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.getQueryItem(named: "test")

        // THEN
        #expect(result == nil)
    }

    @Test("URL.appending(percentEncodedQueryItem:) correctly adds a query item")
    func appendingQueryItemReturnsURLWithQueryItem() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.appending(percentEncodedQueryItem: .init(name: "origin", value: "test"))

        // THEN
        #expect(result.absoluteString == "www.duckduckgo.com?origin=test")
    }

    @Test("URL.appending(percentEncodedQueryItems:) correctly adds multiple query items")
    func appendingQueryItemsReturnsURLWithQueryItems() throws {
        // GIVEN
        let queryItems = [URLQueryItem(name: "origin", value: "test"), URLQueryItem(name: "another_item", value: "test_2")]
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.appending(percentEncodedQueryItems: queryItems)

        // THEN
        #expect(result.absoluteString == "www.duckduckgo.com?origin=test&another_item=test_2")
    }

    @Test("URL.getQueryItems returns all query items for a URL")
    func getQueryItemsReturnsQueryItemsForURL() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com?origin=test&another_item=test_2"))

        // WHEN
        let result = try #require(url.getQueryItems())

        // THEN
        #expect(result.first == .init(name: "origin", value: "test"))
        #expect(result.last == .init(name: "another_item", value: "test_2"))
    }

    @Test("URL.trimmedAddressBarString handles user and password information correctly")
    func userInfoDoesNotContaintPassword_NavigateToSearch() {
        #expect(URL(trimmedAddressBarString: "user@domain.com") == nil)

        let url1 = URL(trimmedAddressBarString: "user: @domain.com")
        #expect(url1?.host == "domain.com")
        #expect(url1?.user(percentEncoded: false) == "user")
        #expect(url1?.password(percentEncoded: false) == " ")

        let url2 = URL(trimmedAddressBarString: "user:,,@domain.com")
        #expect(url2?.host == "domain.com")
        #expect(url2?.user(percentEncoded: false) == "user")
        #expect(url2?.password(percentEncoded: false) == ",,")

        let url3 = URL(trimmedAddressBarString: "user:pass@domain.com")
        #expect(url3?.host == "domain.com")
        #expect(url3?.user(percentEncoded: false) == "user")
        #expect(url3?.password(percentEncoded: false) == "pass")
    }

    @Test("URL handles spaces in path, query, and fragment components")
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

    @Test("URL correctly handles international characters")
    func internationalCharactersInURLComponents() throws {
        // Test with international characters in path
        let urlWithInternationalPath = URL(string: "https://example.com/пример/测试")
        #expect(urlWithInternationalPath?.absoluteString == "https://example.com/%D0%BF%D1%80%D0%B8%D0%BC%D0%B5%D1%80/%E6%B5%8B%E8%AF%95")

        // Test with international characters in query
        let urlWithInternationalQuery = URL(string: "https://example.com/search?q=こんにちは")
        #expect(urlWithInternationalQuery?.absoluteString == "https://example.com/search?q=%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF")
    }

    @Test("URL correctly handles spaces specifically in auth, path, and query parameters")
    func spacesInAuthPathAndQueryParameters() throws {
        // URL with spaces in auth
        let urlWithSpacesInAuth = URL(string: "https://user name:pass word@example.com")
        #expect(urlWithSpacesInAuth?.absoluteString == "https://user%20name:pass%20word@example.com")

        // URL with spaces in path
        let urlWithSpacesInPath = URL(string: "https://example.com/path with/spaces here")
        #expect(urlWithSpacesInPath?.absoluteString == "https://example.com/path%20with/spaces%20here")

        // URL with spaces in query parameters
        let urlWithSpacesInQueryParams = URL(string: "https://example.com/search?query=hello world&category=books and magazines")
        #expect(urlWithSpacesInQueryParams?.absoluteString == "https://example.com/search?query=hello%20world&category=books%20and%20magazines")
    }

    @Test("URL maintains plus signs in query parameters")
    func plusSignsInQueryParametersArePreserved() throws {
        let url = URL(string: "https://example.com/search?q=c++programming&lang=c++")?
            .appendingParameter(name: "rating", value: "4+")

        #expect(url?.absoluteString == "https://example.com/search?q=c++programming&lang=c++&rating=4%2B")
    }

    @Test("URL handles email addresses in mailto: URLs correctly")
    func emailAddressesInMailtoURLs() throws {
        let url = URL(string: "mailto:test@example.com,user@domain.com")
        #expect(url?.absoluteString == "mailto:test@example.com,user@domain.com")

        let emailAddresses = url?.emailAddresses
        #expect(emailAddresses?.count == 2)
        #expect(emailAddresses?[0] == "test@example.com")
        #expect(emailAddresses?[1] == "user@domain.com")
    }

    @Test("URL.removingTextFragment removes text fragment if it exists", arguments: [
        ("example.com#:~:text=abcd%20", "example.com"),
        ("https://youtube.com/watch?v=12345#:~:text=ab%20cd", "https://youtube.com/watch?v=12345"),
        ("https://example.com/#:~:", "https://example.com/"),
        ("https://example.com/#:~:foo", "https://example.com/"),
        ("https://example.com/#anchor", "https://example.com/#anchor"),
        ("https://example.com/#", "https://example.com/#")
    ])
    func removingTextFragment(source: String, processed: String) throws {
        #expect(source.url!.removingTextFragment() == processed.url)
    }

}

extension String {
    var url: URL? {
        return URL(trimmedAddressBarString: self)
    }
    var decodedURL: URL? {
        URL(trimmedAddressBarString: self)
    }
}

extension URL {
    func removeParameter(name: String) -> URL {
        return self.removingParameters(named: [name])
    }

    var emailAddresses: [String]? {
        guard scheme == "mailto" else { return nil }

        // Extract email part after mailto:
        let emailsString = absoluteString.replacingOccurrences(of: "mailto:", with: "")

        // Split by comma and filter out empty strings
        return emailsString.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
