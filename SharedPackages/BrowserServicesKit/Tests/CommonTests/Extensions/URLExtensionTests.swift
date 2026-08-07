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
import OSLog
import Testing

@testable import Common

// swiftlint:disable comma
final class URLExtensionTests {

    @available(iOS 16, macOS 13, *)
    @Test("External URLs are valid", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("Navigational URLs are valid", .timeLimit(.minutes(1)), arguments: navigational_urls_args)
    func navigational_urls_are_valid(rawValue: String, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let url = rawValue.decodedURL
        #expect(url != nil, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        #expect(url!.isValid, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    static let non_valid_urls_args = [
        "about:user:pass@blank",
        "data:user:pass@text/vnd-example+xyz;foo=bar;base64,R0lGODdh",
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Non-valid URLs", .timeLimit(.minutes(1)))
    func non_valid_urls() throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        for item in Self.non_valid_urls_args {
            #expect(item.url == nil)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL scheme is added when missing", .timeLimit(.minutes(1)))
    func when_no_scheme_in_string_url_has_scheme() {
        #expect("duckduckgo.com".url!.absoluteString == "http://duckduckgo.com")
        #expect("example.com".url!.absoluteString == "http://example.com")
        #expect("localhost".url!.absoluteString == "http://localhost")
        #expect("localdomain".url == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("IPv4 addresses must contain four octets", .timeLimit(.minutes(1)))
    func ipv4AddressMustContainFourOctets() {
        #expect("1.4".url == nil)
        #expect("1.4/3.4".url == nil)
        #expect("1.0.4".url == nil)
        #expect("127.0.1".url == nil)

        #expect("127.0.0.1".url?.absoluteString == "http://127.0.0.1")
        #expect("1.0.0.4/3.4".url?.absoluteString == "http://1.0.0.4/3.4")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.naked returns a normalized URL without scheme, www prefix, and trailing slash", .timeLimit(.minutes(1)))
    func nakedIsCalled_returnsURLWithNoSchemeWWWPrefixAndLastSlash() {
        let url = URL(string: "http://duckduckgo.com")!
        let duplicate = URL(string: "https://www.duckduckgo.com/")!

        #expect(url.naked == duplicate.naked)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.root returns a URL with the host only, removing all other components", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("Basic auth credentials are correctly extracted from URLs", .timeLimit(.minutes(1)), arguments: basicAuthCredential_args)
    func basicAuthCredential(url: String, user: String?, password: String?, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let credential = url.decodedURL!.basicAuthCredential
        #expect(credential?.user == user, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        #expect(credential?.password == password, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
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

    @available(iOS 16, macOS 13, *)
    @Test("Basic auth credentials are correctly removed from URLs", .timeLimit(.minutes(1)), arguments: urlRemovingBasicAuthCredential_args)
    func urlRemovingBasicAuthCredential(url: String, removingCredential: String, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let filtered = url.decodedURL!.removingBasicAuthCredential()
        #expect(filtered.absoluteString == removingCredential, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.isRoot correctly identifies root URLs", .timeLimit(.minutes(1)))
    func isRoot() {
        let url = URL(string: "https://www.server.com:8080/path?query=string#fragment")!
        let rootUrl = URL(string: "https://www.server.com:8080/")!

        #expect(rootUrl.isRoot)
        #expect(!url.isRoot)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter doesn't change the original URL", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter correctly encodes RFC3986 reserved characters", .timeLimit(.minutes(1)), arguments: rfc3986QueryReservedChars_args)
    func addParameterIsCalled_encodesRFC3986QueryReservedCharactersInTheParameter(name: String, value: String, expected: String, line: UInt) {
        let url = URL(string: "https://duck.com/")!
        #expect(url.appendingParameter(name: name, value: value).absoluteString == expected, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter allows unescaped reserved characters when specified", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString returns nil for empty input", .timeLimit(.minutes(1)))
    func punycodeUrlIsCalledOnEmptyStringReturnsNil() {
        #expect(URL(trimmedAddressBarString: "")?.absoluteString == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString returns nil for space input", .timeLimit(.minutes(1)))
    func punycodeUrlIsCalledOnQueryReturnsNil() {
        #expect(URL(trimmedAddressBarString: " ")?.absoluteString == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString returns nil for URLs with spaces in the hostname", .timeLimit(.minutes(1)))
    func punycodeUrlIsCalledOnQueryWithSpaceThenUrlIsNotReturned() {
        #expect(URL(trimmedAddressBarString: "https://www.duckduckgo .com/html?q=search")?.absoluteString == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString returns nil for unicode local hostnames", .timeLimit(.minutes(1)))
    func punycodeUrlIsCalledOnLocalHostnameReturnsNil() {
        #expect(URL(trimmedAddressBarString: "💩")?.absoluteString == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString doesn't interpret 'define:' as a local URL", .timeLimit(.minutes(1)))
    func defineSearchRequestIsMadeNotInterpretedAsLocalURL() {
        #expect(URL(trimmedAddressBarString: "define:300/spartans")?.absoluteString == nil)
    }

    static let addressBarURLParsing_args: [(String, String?, String?, UInt)] = [
        ("user@somehost.local:9091/index.html", "http://user@somehost.local:9091/index.html", "http", #line),
        ("something.local:9100", "http://something.local:9100/", "http", #line),
        ("user@localhost:5000", "http://user@localhost:5000/", "http", #line),
        ("user:password@localhost:5000", "http://user:password@localhost:5000/", "http", #line),
        ("localhost", "http://localhost/", "http", #line),
        ("localhost:5000", "http://localhost:5000/", "http", #line),
        ("sms://+44123123123", nil, nil, #line),
        ("mailto:test@example.com", "mailto:test@example.com", "mailto", #line),
        ("mailto:u%24ser@💩.la?arg=b", "mailto:u%24ser@%F0%9F%92%A9.la?arg=b", "mailto", #line), // note: this needs to be fixed in URLPredictorRust to use punycode
        ("http://u%24ser@💩.la?arg=b#1", "http://u%24ser@xn--ls8h.la/?arg=b#1", "http", #line),
        ("62.12.14.111", "http://62.12.14.111/", "http", #line),
        ("https://", nil, nil, #line),
        ("http://duckduckgo.com", "http://duckduckgo.com/", "http", #line),
        ("https://duckduckgo.com", "https://duckduckgo.com/", "https", #line),
        ("https://duckduckgo.com/", "https://duckduckgo.com/", "https", #line),
        ("duckduckgo.com", "http://duckduckgo.com/", "http", #line),
        ("duckduckgo.com/html?q=search", "http://duckduckgo.com/html?q=search", "http", #line),
        ("www.duckduckgo.com", "http://www.duckduckgo.com/", "http", #line),
        ("https://www.duckduckgo.com/html?q=search", "https://www.duckduckgo.com/html?q=search", "https", #line),
        ("https://www.duckduckgo.com/html/?q=search", "https://www.duckduckgo.com/html/?q=search", "https", #line),
        ("ftp://www.duckduckgo.com", nil, nil, #line),
        ("file:///users/user/Documents/afile", "file:///users/user/Documents/afile", "file", #line),
        ("https://www.duckduckgo.com/html?q =search", "https://www.duckduckgo.com/html?q%20=search", "https", #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString correctly parses various address bar inputs", .timeLimit(.minutes(1)), arguments: addressBarURLParsing_args)
    func addressBarURLParsing(address: String, expectedString: String? = nil, expectedScheme: String? = nil, line: UInt) {
        let url = URL(trimmedAddressBarString: address, useUnifiedLogic: true)
        #expect(url?.scheme == expectedScheme, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        #expect(url?.absoluteString == expectedString, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString escapes invalid characters in URL parameters", .timeLimit(.minutes(1)))
    func urlParametersModifiedWithInvalidCharactersThenParametersArePercentEscaped() {
        #expect(URL(trimmedAddressBarString: "https://www.duckduckgo.com/html?q=a%20search with+space?+and%25plus&ia=calculator")!.absoluteString ==
                "https://www.duckduckgo.com/html?q=a%20search%20with+space?+and%25plus&ia=calculator")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString preserves empty query markers", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString escapes hash fragments correctly", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString correctly handles punycode URLs", .timeLimit(.minutes(1)), arguments: punycodeUrls_args)
    func punycodeUrlIsCalledWithEncodedUrlsReturnsCorrectURL(input: String, expected: String, line: UInt) {
        #expect(input.decodedURL?.absoluteString == expected, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getParameter returns the correct value when the parameter exists", .timeLimit(.minutes(1)))
    func paramExistsThengetParameterReturnsCorrectValue() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let expected = "secondValue"
        let actual = url.getParameter(named: "secondParam")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getParameter returns nil when the parameter doesn't exist", .timeLimit(.minutes(1)))
    func paramDoesNotExistThengetParameterIsNil() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let result = url.getParameter(named: "someOtherParam")
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removeParameter returns a URL without the specified parameter", .timeLimit(.minutes(1)))
    func paramExistsThenRemovingReturnUrlWithoutParam() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let expected = URL(string: "http://test.com?secondParam=secondValue")!
        let actual = url.removeParameter(name: "firstParam")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removeParameter returns the same URL when the parameter doesn't exist", .timeLimit(.minutes(1)))
    func paramDoesNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removeParameter(name: "someOtherParam")
        #expect(actual == url)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removeParameter preserves plus signs in remaining parameters", .timeLimit(.minutes(1)))
    func removingAParamThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")!
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")!
        let actual = url.removeParameter(name: "firstParam")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingParameters returns a URL without the specified parameters", .timeLimit(.minutes(1)))
    func removingParamsThenRemovingReturnsUrlWithoutParams() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue&thirdParam=thirdValue")!
        let expected = URL(string: "http://test.com?secondParam=secondValue")!
        let actual = url.removingParameters(named: ["firstParam", "thirdParam"])
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingParameters returns the same URL when no parameters match", .timeLimit(.minutes(1)))
    func paramsDoNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removingParameters(named: ["someParam", "someOtherParam"])
        #expect(actual == url)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingParameters returns the same URL when given an empty array", .timeLimit(.minutes(1)))
    func emptyParamArrayIsUsedThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removingParameters(named: [])
        #expect(actual == url)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingParameters preserves plus signs in remaining parameters", .timeLimit(.minutes(1)))
    func removingParamsThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")!
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")!
        let actual = url.removingParameters(named: ["firstParam"])
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter adds a query string when there are no parameters", .timeLimit(.minutes(1)))
    func noParamsThenAddingAppendsQuery() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=aValue")!
        let actual = url.appendingParameter(name: "aParam", value: "aValue")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter appends to existing query parameters", .timeLimit(.minutes(1)))
    func paramDoesNotExistThenAddingParamAppendsItToExistingQuery() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&anotherParam=anotherValue")!
        let actual = url.appendingParameter(name: "anotherParam", value: "anotherValue")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter encodes parameters with invalid characters", .timeLimit(.minutes(1)))
    func paramHasInvalidCharactersThenAddingParamAppendsEncodedVersion() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=43%20%2B%205")!
        let actual = url.appendingParameter(name: "aParam", value: "43 + 5")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter adds a new value for an existing parameter", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL.matches correctly compares URLs", .timeLimit(.minutes(1)), arguments: matches_comparator_args)
    func matchesComparator(url1: String, url2: String, expected: Bool, line: UInt) {
        if expected {
            #expect(url1.url!.equals(url2.url!, by: .fuzzyIdentity), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        } else {
            #expect(!url1.url!.equals(url2.url!, by: .fuzzyIdentity), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL.matches correctly matches against protection spaces", .timeLimit(.minutes(1)), arguments: matches_protection_space_args)
    func matchesProtectionSpace(url: String, host: String, port: Int, scheme: String, expected: Bool, line: UInt) {
        let protectionSpace = URLProtectionSpace(host: host, port: port, protocol: scheme, realm: "realm", authenticationMethod: "basic")
        if expected {
            #expect(url.url!.matches(protectionSpace), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        } else {
            #expect(!url.url!.matches(protectionSpace), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getQueryItem returns the correct query item when it exists", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL.getQueryItem returns nil when the query item doesn't exist", .timeLimit(.minutes(1)))
    func queryItemWithNameAndURLDoesNotHaveQueryItemReturnsNil() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.getQueryItem(named: "test")

        // THEN
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appending(percentEncodedQueryItem:) correctly adds a query item", .timeLimit(.minutes(1)))
    func appendingQueryItemReturnsURLWithQueryItem() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.appending(percentEncodedQueryItem: .init(name: "origin", value: "test"))

        // THEN
        #expect(result.absoluteString == "www.duckduckgo.com?origin=test")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appending(percentEncodedQueryItems:) correctly adds multiple query items", .timeLimit(.minutes(1)))
    func appendingQueryItemsReturnsURLWithQueryItems() throws {
        // GIVEN
        let queryItems = [URLQueryItem(name: "origin", value: "test"), URLQueryItem(name: "another_item", value: "test_2")]
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.appending(percentEncodedQueryItems: queryItems)

        // THEN
        #expect(result.absoluteString == "www.duckduckgo.com?origin=test&another_item=test_2")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getQueryItems returns all query items for a URL", .timeLimit(.minutes(1)))
    func getQueryItemsReturnsQueryItemsForURL() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com?origin=test&another_item=test_2"))

        // WHEN
        let result = try #require(url.getQueryItems())

        // THEN
        #expect(result.first == .init(name: "origin", value: "test"))
        #expect(result.last == .init(name: "another_item", value: "test_2"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString handles user and password information correctly", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL handles spaces in path, query, and fragment components", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL correctly handles international characters", .timeLimit(.minutes(1)))
    func internationalCharactersInURLComponents() throws {
        // Test with international characters in path
        let urlWithInternationalPath = URL(string: "https://example.com/пример/测试")
        #expect(urlWithInternationalPath?.absoluteString == "https://example.com/%D0%BF%D1%80%D0%B8%D0%BC%D0%B5%D1%80/%E6%B5%8B%E8%AF%95")

        // Test with international characters in query
        let urlWithInternationalQuery = URL(string: "https://example.com/search?q=こんにちは")
        #expect(urlWithInternationalQuery?.absoluteString == "https://example.com/search?q=%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL correctly handles spaces specifically in auth, path, and query parameters", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("URL maintains plus signs in query parameters", .timeLimit(.minutes(1)))
    func plusSignsInQueryParametersArePreserved() throws {
        let url = URL(string: "https://example.com/search?q=c++programming&lang=c++")?
            .appendingParameter(name: "rating", value: "4+")

        #expect(url?.absoluteString == "https://example.com/search?q=c++programming&lang=c++&rating=4%2B")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL handles email addresses in mailto: URLs correctly", .timeLimit(.minutes(1)))
    func emailAddressesInMailtoURLs() throws {
        let url = URL(string: "mailto:test@example.com,user@domain.com")
        #expect(url?.absoluteString == "mailto:test@example.com,user@domain.com")

        let emailAddresses = url?.emailAddresses
        #expect(emailAddresses?.count == 2)
        #expect(emailAddresses?[0] == "test@example.com")
        #expect(emailAddresses?[1] == "user@domain.com")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingTextFragment removes text fragment if it exists", .timeLimit(.minutes(1)), arguments: [
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

// MARK: - URLEqualityComponentsTests

final class URLEqualityComponentsTests {

    // MARK: - hasFragment

    @available(iOS 16, macOS 13, *)
    @Test("hasFragment — hierarchical URL with literal fragment", .timeLimit(.minutes(1)))
    func hasFragment_hierarchical() {
        #expect(URL(string: "https://example.com/#section")!.hasFragment)
        #expect(URL(string: "https://example.com/page#anchor")!.hasFragment)
        #expect(!URL(string: "https://example.com/")!.hasFragment)
        #expect(URL(string: "https://example.com/#")!.hasFragment)
        #expect(!URL(string: "https://example.com")!.hasFragment)
        #expect(URL(string: "https://example.com#")!.hasFragment)
    }

    @available(iOS 16, macOS 13, *)
    @Test("hasFragment — opaque URL (native) with literal # is recognised", .timeLimit(.minutes(1)))
    func hasFragment_opaque_nativeURL_literalHash() {
        #expect(URL(string: "about:blank#section")!.hasFragment)
        #expect(!URL(string: "about:blank")!.hasFragment)
        #expect(URL(string: "about:blank#")!.hasFragment)
    }

    @available(iOS 16, macOS 13, *)
    @Test("hasFragment — opaque URL with %23 and no WebKit string: fragment NOT detected", .timeLimit(.minutes(1)))
    func hasFragment_opaque_percentEncoded_noWebKitString() {
        // Without _web_originalDataAsString, URLComponents(webKitUrl:) falls back to
        // URLComponents(url:), which treats %23 as part of the path — not a fragment delimiter.
        #expect(!URL(string: "about:blank%23section")!.hasFragment)
        #expect(!(NSURL(string: "about:blank%23section")! as URL).hasFragment)
        #expect(!URL(string: "data:text/html,hello%23anchor")!.hasFragment)
    }

    @available(iOS 16, macOS 13, *)
    @Test("hasFragment — opaque URL with literal # in data: and about: schemes", .timeLimit(.minutes(1)))
    func hasFragment_opaque_literalHash_dataAndAbout() {
        #expect(URL(string: "about:blank#section")!.hasFragment)
        #expect(!URL(string: "about:blank")!.hasFragment)
        #expect(URL(string: "about:blank#")!.hasFragment)
        #expect(URL(string: "data:text/html,hello#anchor")!.hasFragment)
        #expect(URL(string: "data:text/html,hello#")!.hasFragment)
        #expect(!URL(string: "data:text/html,hello")!.hasFragment)
        #expect(!URL(string: "data:text/html,hello%23world!")!.hasFragment)
    }

    // MARK: - originalWebKitString

#if _ORIGINAL_DATA_AS_STRING_ENABLED
    @available(iOS 16, macOS 13, *)
    @Test("originalWebKitString — returns the URL's absolute string", .timeLimit(.minutes(1)))
    func originalWebKitString_returnsAbsoluteString() {
        let url = URL(string: "about:blank#section")!
        #expect(url.originalWebKitString == "about:blank#section")
    }
#endif

    // MARK: - equals — individual component masks (hierarchical URLs)

    @available(iOS 16, macOS 13, *)
    @Test("equals([.scheme]) — scheme only, ignores host/port/path/query/fragment", .timeLimit(.minutes(1)))
    func equalsSchemeOnly() {
        let a = URL(string: "https://example.com:8080/path?q=1#frag")!
        #expect(a.equals(URL(string: "https://other.com:9090/different?q=2#other")!, by: [.scheme]))
        #expect(!a.equals(URL(string: "http://example.com:8080/path?q=1#frag")!, by: [.scheme]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals([.host]) — host only, ignores scheme/port/path/query/fragment", .timeLimit(.minutes(1)))
    func equalsHostOnly() {
        let a = URL(string: "https://example.com:443/path?q=1#frag")!
        #expect(a.equals(URL(string: "http://example.com:80/other?q=2#other")!, by: [.host]))
        #expect(!a.equals(URL(string: "https://other.com:443/path?q=1#frag")!, by: [.host]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals([.port]) — port only, including nil (absent) vs explicit port", .timeLimit(.minutes(1)))
    func equalsPortOnly() {
        let a = URL(string: "https://example.com:8080/path")!
        #expect(a.equals(URL(string: "http://other.com:8080/different")!, by: [.port]))
        #expect(!a.equals(URL(string: "https://example.com:9090/path")!, by: [.port]))
        #expect(!a.equals(URL(string: "https://example.com/path")!, by: [.port]))  // 8080 vs nil
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals([.path]) — path only; trailing slash is normalised", .timeLimit(.minutes(1)))
    func equalsPathOnly() {
        let a = URL(string: "https://example.com:443/path/to/page?q=1#frag")!
        #expect(a.equals(URL(string: "http://other.com/path/to/page?q=2#other")!, by: [.path]))
        #expect(!a.equals(URL(string: "https://example.com/different/path")!, by: [.path]))
        #expect(a.equals(URL(string: "https://example.com/path/to/page/")!, by: [.path]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals([.query]) — query only, ignores scheme/host/port/path/fragment", .timeLimit(.minutes(1)))
    func equalsQueryOnly() {
        let a = URL(string: "https://example.com/path?q=1&p=2#frag")!
        #expect(a.equals(URL(string: "http://other.com/other?q=1&p=2#other")!, by: [.query]))
        #expect(!a.equals(URL(string: "https://example.com/path?q=2&p=2")!, by: [.query]))
        #expect(!a.equals(URL(string: "https://example.com/path")!, by: [.query]))  // q=1&p=2 vs nil
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals([.fragment]) — fragment only, ignores scheme/host/port/path/query", .timeLimit(.minutes(1)))
    func equalsFragmentOnly() {
        let a = URL(string: "https://example.com/path?q=1#frag")!
        #expect(a.equals(URL(string: "http://other.com/other?q=2#frag")!, by: [.fragment]))
        #expect(!a.equals(URL(string: "https://example.com/path?q=1#other")!, by: [.fragment]))
        #expect(!a.equals(URL(string: "https://example.com/path")!, by: [.fragment]))  // "frag" vs nil
    }

    // MARK: - equals — component combinations (hierarchical URLs)

    @available(iOS 16, macOS 13, *)
    @Test("equals([.scheme, .host]) — ignores port, path, query, fragment", .timeLimit(.minutes(1)))
    func equalsSchemeAndHost() {
        let a = URL(string: "https://example.com:8080/path?q=1#frag")!
        #expect(a.equals(URL(string: "https://example.com:9090/other?q=2#other")!, by: [.scheme, .host]))
        #expect(!a.equals(URL(string: "http://example.com:8080/path?q=1#frag")!, by: [.scheme, .host]))
        #expect(!a.equals(URL(string: "https://other.com:8080/path")!, by: [.scheme, .host]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals([.scheme, .host, .port]) — origin equality", .timeLimit(.minutes(1)))
    func equalsOrigin() {
        let a = URL(string: "https://example.com:8080/path?q=1")!
        #expect(a.equals(URL(string: "https://example.com:8080/other?q=2#frag")!, by: [.scheme, .host, .port]))
        #expect(!a.equals(URL(string: "https://example.com:9090/path?q=1")!, by: [.scheme, .host, .port]))
        #expect(!a.equals(URL(string: "http://example.com:8080/path?q=1")!, by: [.scheme, .host, .port]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals([.path, .query]) — ignores scheme/host/port/fragment", .timeLimit(.minutes(1)))
    func equalsPathAndQuery() {
        let a = URL(string: "https://example.com/path?q=1#frag")!
        #expect(a.equals(URL(string: "http://other.com:8080/path?q=1#other")!, by: [.path, .query]))
        #expect(!a.equals(URL(string: "https://example.com/path?q=2")!, by: [.path, .query]))
        #expect(!a.equals(URL(string: "https://example.com/path")!, by: [.path, .query]))  // q=1 vs nil
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals([.path, .fragment]) — ignores scheme/host/port/query", .timeLimit(.minutes(1)))
    func equalsPathAndFragment() {
        let a = URL(string: "https://example.com/path?q=1#frag")!
        #expect(a.equals(URL(string: "http://other.com:123/path?x=9#frag")!, by: [.path, .fragment]))
        #expect(!a.equals(URL(string: "https://example.com/path?q=1#other")!, by: [.path, .fragment]))
        #expect(!a.equals(URL(string: "https://example.com/different#frag")!, by: [.path, .fragment]))
    }

    // MARK: - equals(.sameDocument) — parameterised (hierarchical + opaque with literal #)

    static let sameDocument_args: [(String, String, Bool, UInt)] = [
        // Same URL, no fragment → equal
        ("http://example.com/page",       "http://example.com/page",        true,  #line),
        // Different fragments → same document (fragment is ignored)
        ("http://example.com/page#a",     "http://example.com/page#b",      true,  #line),
        ("http://example.com/page#a",     "http://example.com/page",        true,  #line),
        // Different path → not same document
        ("http://example.com/page",       "http://example.com/other",       false, #line),
        ("http://example.com/path",       "http://example.com/",            false, #line),
        // Different query → not same document
        ("http://example.com/page?q=1",   "http://example.com/page?q=2",    false, #line),
        ("http://example.com/page?q=1",   "http://example.com/page",        false, #line),
        ("http://example.com/page?q#a",   "http://example.com/page",        false, #line),
        // Different scheme → not same document
        ("http://example.com/page",       "https://example.com/page",       false, #line),
        // Different host → not same document
        ("http://example.com/page",       "http://other.com/page",          false, #line),
        ("http://example.com/#hash",      "file://example.com",             false, #line),
        // Different port → not same document
        ("http://example.com:8080/page",  "http://example.com:9090/page",   false, #line),
        ("http://example.com:81/",        "http://example.com/",            false, #line),
        // Explicit non-default port: same port ± fragment → same document
        ("http://example.com:81/#hash",   "http://example.com:81/",         true,  #line),
        ("http://example.com:81/p#hash",  "http://example.com:81/p",        true,  #line),
        // about: with literal # — same document regardless of fragment
        ("about:blank",                   "about:blank",                    true,  #line),
        ("about:blank#section",           "about:blank",                    true,  #line),
        ("about:blank#a",                 "about:blank#b",                  true,  #line),
        // file://
        ("file:///path/to/file.html",     "file:///path/to/file.html",      true,  #line),
        ("file:///path/to/file.html#a",   "file:///path/to/file.html",      true,  #line),
        ("file:///path/to/file.html?q",   "file:///path/to/file.html",      false, #line),
        ("file:///path/to/other.html",    "file:///path/to/file.html",      false, #line),
        // data: — different opaque payloads → not same document
        ("data:text/plain,hello",         "data:text/plain,world",          false, #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("equals(.sameDocument) — fragment-blind equality, native URL(string:)",
          .timeLimit(.minutes(1)), arguments: sameDocument_args)
    func equalsSameDocument(url1: String, url2: String, expected: Bool, line: UInt) {
#if !_ORIGINAL_DATA_AS_STRING_ENABLED
        guard ![url1, url2].contains(where: { $0.contains("about:blank#") }) else {
            Logger.general.warning("Skipping \(url1) / \(url2) because _ORIGINAL_DATA_AS_STRING_ENABLED is not enabled")
            return
        }
#endif

        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        guard let a = URL(string: url1), let b = URL(string: url2) else {
            Issue.record("Could not construct URLs: \(url1) / \(url2)", sourceLocation: loc); return
        }
        #expect(a.equals(b, by: .sameDocument) == expected, sourceLocation: loc)
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals(.sameDocument) — same result when URLs are created via NSURL",
          .timeLimit(.minutes(1)), arguments: sameDocument_args)
    func equalsSameDocument_NSURL(url1: String, url2: String, expected: Bool, line: UInt) {
#if !_ORIGINAL_DATA_AS_STRING_ENABLED
        guard ![url1, url2].contains(where: { $0.contains("about:blank#") }) else {
            Logger.general.warning("Skipping \(url1) / \(url2) because _ORIGINAL_DATA_AS_STRING_ENABLED is not enabled")
            return
        }
#endif

        guard let a = NSURL(string: url1) as URL?, let b = NSURL(string: url2) as URL? else { return }
        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        #expect(a.equals(b, by: .sameDocument) == expected, sourceLocation: loc)
    }

    // MARK: - equals(.fuzzyIdentity) — parameterised

    static let fuzzyIdentity_args: [(String, String, Bool, UInt)] = [
        // Identical URL → equal
        ("http://example.com/page",       "http://example.com/page",        true,  #line),
        // Same fragment → equal
        ("https://example.com/page#sec",  "https://example.com/page#sec",   true,  #line),
        ("https://example.com/#link#1",   "https://example.com#link#1",     true,  #line),
        // Different fragments → not equal
        ("http://example.com/page#a",     "http://example.com/page#b",      false, #line),
        ("http://example.com/page#frag",  "http://example.com/page",        false, #line),
        // Different scheme → not equal
        ("https://example.com/page",      "http://example.com/page",        false, #line),
        // Different host → not equal
        ("http://example.com/page",       "http://other.com/page",          false, #line),
        // Different port → not equal
        ("http://example.com:8080/",      "http://example.com:9090/",       false, #line),
        // Different path → not equal
        ("http://example.com/a",          "http://example.com/b",           false, #line),
        // Trailing slash is normalised
        ("http://example.com/page/",      "http://example.com/page",        true,  #line),
        // about: with literal # → fragment distinguished
        ("about:blank#section",           "about:blank#section",            true,  #line),
        ("about:blank#section",           "about:blank#other",              false, #line),
        ("about:blank#section",           "about:blank",                    false, #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("equals(.fuzzyIdentity) — fragment-sensitive, native URL(string:)",
          .timeLimit(.minutes(1)), arguments: fuzzyIdentity_args)
    func equalsFuzzyIdentity(url1: String, url2: String, expected: Bool, line: UInt) {
        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        guard let a = URL(string: url1), let b = URL(string: url2) else {
            Issue.record("Could not construct URLs: \(url1) / \(url2)", sourceLocation: loc); return
        }
        #expect(a.equals(b, by: .fuzzyIdentity) == expected, sourceLocation: loc)
    }

    @available(iOS 16, macOS 13, *)
    @Test("equals(.fuzzyIdentity) — same result when URLs are created via NSURL",
          .timeLimit(.minutes(1)), arguments: fuzzyIdentity_args)
    func equalsFuzzyIdentity_NSURL(url1: String, url2: String, expected: Bool, line: UInt) {
        guard let a = NSURL(string: url1) as URL?, let b = NSURL(string: url2) as URL? else { return }
        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        #expect(a.equals(b, by: .fuzzyIdentity) == expected, sourceLocation: loc)
    }

    // MARK: - equals — opaque about: URLs

    @available(iOS 16, macOS 13, *)
    @Test("equals — about: sameDocument ignores fragment, fuzzyIdentity distinguishes",
          .timeLimit(.minutes(1)))
    func opaque_aboutURL_fragmentAwareness() {
        let blank  = URL(string: "about:blank")!
        let sec    = URL(string: "about:blank#section")!
        let other  = URL(string: "about:blank#other")!

        // sameDocument: path "blank" == "blank" for all three
        #expect(blank.equals(sec,   by: .sameDocument))
        #expect(blank.equals(other, by: .sameDocument))
        #expect(sec.equals(other,   by: .sameDocument))

        // fuzzyIdentity: fragment nil / "section" / "other" all differ
        #expect(!blank.equals(sec,   by: .fuzzyIdentity))
        #expect(!blank.equals(other, by: .fuzzyIdentity))
        #expect(!sec.equals(other,   by: .fuzzyIdentity))

        // individual components
        #expect(blank.equals(sec,  by: [.scheme]))    // "about" == "about"
        #expect(blank.equals(sec,  by: [.path]))      // "blank" == "blank"
        #expect(!blank.equals(sec, by: [.fragment]))  // nil != "section"
        #expect(!sec.equals(other, by: [.fragment]))  // "section" != "other"
        #expect(sec.equals(other,  by: [.path]))      // "blank" == "blank"
    }

    // MARK: - equals — opaque data: URLs

    @available(iOS 16, macOS 13, *)
    @Test("equals — data: path and fragment separated correctly",
          .timeLimit(.minutes(1)))
    func opaque_dataURL_pathAndFragmentSeparated() {
        let noFrag   = URL(string: "data:text/html,hello")!
        let anchor   = URL(string: "data:text/html,hello#anchor")!
        let other    = URL(string: "data:text/html,hello#other")!
        let diffPath = URL(string: "data:text/html,world#anchor")!
        let sameAnchor = URL(string: "data:text/html,hello#anchor2")!

        // sameDocument: path must match, fragment ignored
        #expect(noFrag.equals(anchor,   by: .sameDocument))
        #expect(noFrag.equals(other,    by: .sameDocument))
        #expect(anchor.equals(other,    by: .sameDocument))
        #expect(!noFrag.equals(diffPath, by: .sameDocument))   // "hello" != "world"

        // fuzzyIdentity: fragment included
        #expect(!noFrag.equals(anchor,   by: .fuzzyIdentity))  // nil vs "anchor"
        #expect(!anchor.equals(other,    by: .fuzzyIdentity))  // "anchor" vs "other"
        #expect(!noFrag.equals(diffPath, by: .fuzzyIdentity))

        // [.path] only
        #expect(noFrag.equals(anchor,  by: [.path]))           // "text/html,hello"
        #expect(!noFrag.equals(diffPath, by: [.path]))         // hello != world

        // [.fragment] only
        #expect(!noFrag.equals(anchor, by: [.fragment]))       // nil vs "anchor"
        #expect(!anchor.equals(other,  by: [.fragment]))       // "anchor" vs "other"
        #expect(anchor.equals(                                 // both "anchor"
            URL(string: "data:text/html,world#anchor")!,
            by: [.fragment]))

        // [.path, .query]: no query present → path comparison only
        #expect(noFrag.equals(anchor,   by: [.path, .query]))
        #expect(!noFrag.equals(diffPath, by: [.path, .query]))

        // [.path, .fragment]: path must also match
        #expect(!noFrag.equals(anchor,     by: [.path, .fragment]))   // fragment nil vs "anchor"
        #expect(anchor.equals(sameAnchor,  by: [.path]))              // "hello" == "hello"
        #expect(!anchor.equals(sameAnchor, by: [.fragment]))          // "anchor" vs "anchor2"
        #expect(!anchor.equals(sameAnchor, by: [.path, .fragment]))   // path same, frag differs
    }

    // MARK: - Foundation contracts and NSURL behaviour

    @available(iOS 16, macOS 13, *)
    @Test("URL.fragment is nil for opaque URL with %23 (Foundation contract)", .timeLimit(.minutes(1)))
    func foundationOpaqueURLPercentEncodedFragmentIsNil() {
        let cases = ["about:blank%23section", "about:blank%23", "data:text/html,hello%23world"]
        for raw in cases {
            #expect(URL(string: raw)?.fragment == nil, "URL.fragment should be nil for \(raw)")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("URLComponents.fragment is nil for opaque URL with %23 (Foundation contract)", .timeLimit(.minutes(1)))
    func foundationOpaqueURLPercentEncodedFragmentNilInURLComponents() {
        let cases = ["about:blank%23section", "about:srcdoc?html=x%23sec"]
        for raw in cases {
            guard let url = URL(string: raw),
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            #expect(comps.fragment == nil, "URLComponents.fragment should be nil for \(raw)")
        }
    }

#if _ORIGINAL_DATA_AS_STRING_ENABLED
    @available(iOS 16, macOS 13, *)
    @Test("NSURL with literal # fragment: sameDocument true, fuzzyIdentity detects fragment",
          .timeLimit(.minutes(1)))
    func nsURL_literalHashFragment_equality() {
        let blank  = NSURL(string: "about:blank")! as URL
        let hashed = NSURL(string: "about:blank#section")! as URL

        // sameDocument: fragment is ignored → true
        #expect(blank.equals(hashed, by: .sameDocument))
        // fuzzyIdentity: nil vs "section" → false
        #expect(!blank.equals(hashed, by: .fuzzyIdentity))

        // Two NSURL about:blank#section instances are equal under fuzzyIdentity
        let other = URL(string: "about:blank#section")!
        #expect(hashed.equals(other, by: .fuzzyIdentity))
    }
#else
    // Without _web_originalDataAsString, NSURL percent-encodes '#' to '%23', folding the
    // fragment token into the path string. Components that don't touch the path (scheme,
    // host, port, query, fragment) are unaffected and still compare correctly; any mask
    // that includes .path returns false because "blank" ≠ "blank%23section".
    static let nsURL_percentEncodedHash_args: [(String, String, URL.EqualityComponents, Bool, UInt)] = [
        // No fragments — NSURL produces no %23 encoding; all components compare correctly
        ("about:blank",          "about:blank",                 .sameDocument,  true,  #line),
        ("about:blank",          "about:blank",                 .fuzzyIdentity, true,  #line),
        ("about:blank",          "about:blank",                 [.scheme],      true,  #line),
        ("about:blank",          "about:blank",                 [.path],        true,  #line),
        ("data:text/html,hello", "data:text/html,hello",        .sameDocument,  true,  #line),
        ("data:text/html,hello", "data:text/html,world",        [.scheme],      true,  #line),   // "data" == "data"
        ("data:text/html,hello", "data:text/html,world",        [.path],        false, #line),   // "text/html,hello" ≠ "text/html,world"
        ("data:text/html,hello", "data:text/html,world",        .sameDocument,  false, #line),

        // about:blank vs about:blank#section — NSURL stores second as "about:blank%23section"
        ("about:blank",          "about:blank#section",         [.scheme],      true,  #line),  // "about" == "about"
        ("about:blank",          "about:blank#section",         [.host],        false, #line),  // both nil → skipped → no match
        ("about:blank",          "about:blank#section",         [.port],        false, #line),  // both nil → skipped → no match
        ("about:blank",          "about:blank#section",         [.query],       false, #line),  // both nil → skipped → no match
        ("about:blank",          "about:blank#section",         [.fragment],    false, #line),  // both nil (%23 absorbed into path) → skipped → no match
        ("about:blank",          "about:blank#section",         [.path],        false, #line),  // "blank" ≠ "blank%23section"
        ("about:blank",          "about:blank#section",         .sameDocument,  false, #line),
        ("about:blank",          "about:blank#section",         .fuzzyIdentity, false, #line),
        // about:blank#a vs about:blank#b — "blank%23a" ≠ "blank%23b"
        ("about:blank#a",        "about:blank#b",               [.scheme],      true,  #line),
        ("about:blank#a",        "about:blank#b",               [.host],        false, #line),  // both nil → skipped → no match
        ("about:blank#a",        "about:blank#b",               [.port],        false, #line),  // both nil → skipped → no match
        ("about:blank#a",        "about:blank#b",               [.query],       false, #line),  // both nil → skipped → no match
        ("about:blank#a",        "about:blank#b",               [.fragment],    false, #line),  // both nil (%23 absorbed into path) → skipped → no match
        ("about:blank#a",        "about:blank#b",               [.path],        false, #line),  // "blank%23a" ≠ "blank%23b"
        ("about:blank#a",        "about:blank#b",               .sameDocument,  false, #line),
        ("about:blank#a",        "about:blank#b",               .fuzzyIdentity, false, #line),
        // data: URLs with fragment — "text/html,hello" ≠ "text/html,hello%23anchor"
        ("data:text/html,hello", "data:text/html,hello#anchor", [.scheme],      true,  #line),
        ("data:text/html,hello", "data:text/html,hello#anchor", [.host],        false, #line),  // both nil → skipped → no match
        ("data:text/html,hello", "data:text/html,hello#anchor", [.port],        false, #line),  // both nil → skipped → no match
        ("data:text/html,hello", "data:text/html,hello#anchor", [.query],       false, #line),  // both nil → skipped → no match
        ("data:text/html,hello", "data:text/html,hello#anchor", [.fragment],    false, #line),  // both nil (%23 absorbed into path) → skipped → no match
        ("data:text/html,hello", "data:text/html,hello#anchor", [.path],        false, #line),
        ("data:text/html,hello", "data:text/html,hello#anchor", .sameDocument,  false, #line),
        ("data:text/html,hello", "data:text/html,hello#anchor", .fuzzyIdentity, false, #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("NSURL opaque URL with percent-encoded hash: equals false without _ORIGINAL_DATA_AS_STRING_ENABLED",
          .timeLimit(.minutes(1)), arguments: nsURL_percentEncodedHash_args)
    func nsURL_percentEncodedHash_equalsWithoutFlag(
        url1: String, url2: String, components: URL.EqualityComponents, expected: Bool, line: UInt
    ) {
        guard let a = NSURL(string: url1) as URL?,
              let b = NSURL(string: url2) as URL? else { return }
        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        #expect(a.equals(b, by: components) == expected, sourceLocation: loc)
    }
#endif

    @available(iOS 16, macOS 13, *)
    @Test("equals — about: literal # fragments: sameDocument equal, fuzzyIdentity distinct",
          .timeLimit(.minutes(1)))
    func opaque_aboutURL_fragmentEquality() {
        let sec   = URL(string: "about:blank#section")!
        let other = URL(string: "about:blank#other")!

        #expect(!sec.equals(other, by: .fuzzyIdentity))
        #expect(!sec.equals(other, by: [.fragment]))
        // sameDocument ignores fragment → still equal
        #expect(sec.equals(other, by: .sameDocument))
    }

    // MARK: - Performance

#if _ORIGINAL_DATA_AS_STRING_ENABLED
    @available(iOS 16, macOS 13, *)
    @Test("equals(.sameDocument) completes in reasonable time for a 20 MB data: URI", .timeLimit(.minutes(1)))
    func equalsSameDocumentCompletesForLargeDataURL() {
        let payload  = String(repeating: "A", count: 20 * 1024 * 1024)
        let anchor   = String(repeating: "z", count: 1024 * 1024)
        let base     = "data:text/html," + payload
        let withFrag = base + "#" + anchor

        // Use NSURL so originalWebKitString returns the original string and
        // URLComponents(webKitUrl:) exercises the large-string parsing path.
        guard let url1 = NSURL(string: base) as URL?,
              let url2 = NSURL(string: withFrag) as URL? else {
            Issue.record("Failed to construct 20 MB data: URLs"); return
        }

        let start   = Date()
        let result  = url1.equals(url2, by: .sameDocument)
        let elapsed = Date().timeIntervalSince(start)

        #expect(result == true)
        #expect(elapsed < 0.3, "equals(.sameDocument) took \(elapsed)s — should not be O(n²)")
        Logger.general.info("equalsSameDocumentCompletesForLargeDataURL: \(elapsed)s")

        // fuzzyIdentity must detect absent-vs-present fragment
        #expect(!url1.equals(url2, by: .fuzzyIdentity),
                "url1 has no fragment, url2 has one — must differ under fuzzyIdentity")
    }
#endif

}
// swiftlint:enable comma
