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

import XCTest

@testable import Common

final class URLExtensionTests: XCTestCase {

    func test_external_urls_are_valid() {
        XCTAssertTrue("mailto://user@host.tld".url!.isValid)
        XCTAssertTrue("sms://+44776424232323".url!.isValid)
        XCTAssertTrue("ftp://example.com".url!.isValid)
    }

    func test_navigational_urls_are_valid() throws {
        if #available(macOS 14, *) {
            throw XCTSkip("This test can't run on macOS 14 or higher")
        }

        struct TestItem {
            let rawValue: String
            let line: UInt
            init(_ rawValue: String, line: UInt = #line) {
                self.rawValue = rawValue
                self.line = line
            }
            var url: URL? {
                rawValue.decodedURL
            }
        }
        let urls: [TestItem] = [
            .init("http://example.com"),
            .init("https://example.com"),
            .init("http://localhost"),
            .init("http://localdomain"),
            .init("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment"),
            .init("user@somehost.local:9091/index.html"),
            .init("user:@something.local:9100"),
            .init("user:%20@localhost:5000"),
            .init("user:passwOrd@localhost:5000"),
            .init("user%40local:pa%24%24s@localhost:5000"),
            .init("mailto:test@example.com"),
            .init("192.168.1.1"),
            .init("http://192.168.1.1"),
            .init("http://sheep%2B:P%40%24swrd@192.168.1.1"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1/"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1:8900/"),
            .init("sheep%2B:P%40%24swrd@💩.la?arg=b#1"),
            .init("sheep%2B:P%40%24swrd@xn--ls8h.la/?arg=b#1"),
            .init("https://sheep%2B:P%40%24swrd@💩.la"),
            .init("data:text/vnd-example+xyz;foo=bar;base64,R0lGODdh"),
            .init("http://192.168.0.1"),
            .init("http://203.0.113.0"),
            .init("http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]"),
            .init("http://[2001:0db8::1]"),
            .init("http://[::]:8080")
        ]
        for item in urls {
            XCTAssertNotNil(item.url, "URL is nil: \(item.rawValue)")
            XCTAssertTrue(item.url!.isValid, item.rawValue, line: item.line)
        }
    }

    func test_non_valid_urls() throws {
        if #available(macOS 14, *) {
            throw XCTSkip("This test can't run on macOS 14 or higher")
        }

        let urls = [
            "about:user:pass@blank",
            "data:user:pass@text/vnd-example+xyz;foo=bar;base64,R0lGODdh",
        ]
        for item in urls {
            XCTAssertNil(item.url)
        }
    }

    func test_when_no_scheme_in_string_url_has_scheme() {
        XCTAssertEqual("duckduckgo.com".url!.absoluteString, "http://duckduckgo.com")
        XCTAssertEqual("example.com".url!.absoluteString, "http://example.com")
        XCTAssertEqual("localhost".url!.absoluteString, "http://localhost")
        XCTAssertNil("localdomain".url)
    }

    func testThatIPv4AddressMustContainFourOctets() {
        XCTAssertNil("1.4".url)
        XCTAssertNil("1.4/3.4".url)
        XCTAssertNil("1.0.4".url)
        XCTAssertNil("127.0.1".url)

        XCTAssertEqual("127.0.0.1".url?.absoluteString, "http://127.0.0.1")
        XCTAssertEqual("1.0.0.4/3.4".url?.absoluteString, "http://1.0.0.4/3.4")
    }

    func testWhenNakedIsCalled_ThenURLWithNoSchemeWWWPrefixAndLastSlashIsReturned() {
        let url = URL(string: "http://duckduckgo.com")!
        let duplicate = URL(string: "https://www.duckduckgo.com/")!

        XCTAssertEqual(url.naked, duplicate.naked)
    }

    func testWhenRootIsCalled_ThenURLWithNoPathQueryFragmentUserAndPasswordIsReturned() {
        let url = URL(string: "https://dax:123456@www.duckduckgo.com/test.php?test=S&info=test#fragment")!

        let rootUrl = url.root!
        XCTAssertEqual(rootUrl, URL(string: "https://www.duckduckgo.com/")!)
        XCTAssert(rootUrl.isRoot)
    }

    func testBasicAuthCredential() throws {
        if #available(macOS 14, *) {
            throw XCTSkip("This test can't run on macOS 14 or higher")
        }

        struct TestItem {
            let url: String
            let user: String?
            let password: String?
            let line: UInt
            init(_ url: String, _ user: String?, _ password: String?, line: UInt = #line) {
                self.url = url
                self.user = user
                self.password = password
                self.line = line
            }
        }
        let urls: [TestItem] = [
            .init("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment", "dax@duck.com", "123:456A"),
            .init("user@somehost.local:9091/index.html", "user", ""),
            .init("user:@something.local:9100", "user", ""),
            .init("user:%20@localhost:5000", "user", " "),
            .init("user:passwOrd@localhost:5000", "user", "passwOrd"),
            .init("user%40local:pa%24%24@localhost:5000", "user@local", "pa$$"),
            .init("mailto:test@example.com", nil, nil),
            .init("sheep%2B:P%40%24swrd@💩.la", "sheep+", "P@$swrd"),
            .init("sheep%2B:P%40%24swrd@xn--ls8h.la/", "sheep+", "P@$swrd"),
            .init("https://sheep%2B:P%40%24swrd@💩.la", "sheep+", "P@$swrd"),
            .init("http://sheep%2B:P%40%24swrd@192.168.1.1", "sheep+", "P@$swrd"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1", "sheep+", "P@$swrd"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1/", "sheep+", "P@$swrd"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1:8900/", "sheep+", "P@$swrd"),
        ]

        for item in urls {
            let credential = item.url.decodedURL!.basicAuthCredential
            XCTAssertEqual(credential?.user, item.user, item.url, line: item.line)
            XCTAssertEqual(credential?.password, item.password, item.url, line: item.line)
        }
    }

    func testURLRemovingBasicAuthCredential() throws {
        if #available(macOS 14, *) {
            throw XCTSkip("This test can't run on macOS 14 or higher")
        }

        struct TestItem {
            let url: String
            let removingCredential: String
            let line: UInt
            init(_ url: String, _ removingCredential: String, line: UInt = #line) {
                self.url = url
                self.removingCredential = removingCredential
                self.line = line
            }
        }
        let urls: [TestItem] = [
            .init("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment", "https://www.duckduckgo.com/test.php?test=S&info=test#fragment"),
            .init("user@somehost.local:9091/index.html", "http://somehost.local:9091/index.html"),
            .init("user:@something.local:9100", "http://something.local:9100"),
            .init("user:%20@localhost:5000", "http://localhost:5000"),
            .init("user:passwOrd@localhost:5000", "http://localhost:5000"),
            .init("user%40local:pa%24%24s@localhost:5000", "http://localhost:5000"),
            .init("mailto:test@example.com", "mailto:test@example.com"),
            .init("sheep%2B:P%40%24swrd@💩.la", "http://xn--ls8h.la"),
            .init("sheep%2B:P%40%24swrd@xn--ls8h.la/", "http://xn--ls8h.la/"),
            .init("https://sheep%2B:P%40%24swrd@💩.la", "https://xn--ls8h.la"),
            .init("http://sheep%2B:P%40%24swrd@192.168.1.1", "http://192.168.1.1"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1", "http://192.168.1.1"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1/", "http://192.168.1.1/"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1:8900", "http://192.168.1.1:8900"),
            .init("sheep%2B:P%40%24swrd@192.168.1.1:8900/", "http://192.168.1.1:8900/"),
        ]

        for item in urls {
            let filtered = item.url.decodedURL!.removingBasicAuthCredential()
            XCTAssertEqual(filtered.absoluteString, item.removingCredential, line: item.line)
        }
    }

    func testIsRoot() {
        let url = URL(string: "https://www.server.com:8080/path?query=string#fragment")!
        let rootUrl = URL(string: "https://www.server.com:8080/")!

        XCTAssert(rootUrl.isRoot)
        XCTAssertFalse(url.isRoot)
    }

    func testWhenAddParameterIsCalled_ThenItDoesNotChangeExistingURL() {
        let url = URL(string: "https://duckduckgo.com/?q=Battle%20star+Galactica%25a")!

        XCTAssertEqual(
            url.appendingParameter(name: "ia", value: "web"),
            URL(string: "https://duckduckgo.com/?q=Battle%20star+Galactica%25a&ia=web")!
        )
    }

    func testWhenAddParameterIsCalled_ThenItEncodesRFC3986QueryReservedCharactersInTheParameter() {
        let url = URL(string: "https://duck.com/")!

        XCTAssertEqual(url.appendingParameter(name: ":", value: ":"), URL(string: "https://duck.com/?%3A=%3A")!)
        XCTAssertEqual(url.appendingParameter(name: "/", value: "/"), URL(string: "https://duck.com/?%2F=%2F")!)
        XCTAssertEqual(url.appendingParameter(name: "?", value: "?"), URL(string: "https://duck.com/?%3F=%3F")!)
        XCTAssertEqual(url.appendingParameter(name: "#", value: "#"), URL(string: "https://duck.com/?%23=%23")!)
        XCTAssertEqual(url.appendingParameter(name: "[", value: "["), URL(string: "https://duck.com/?%5B=%5B")!)
        XCTAssertEqual(url.appendingParameter(name: "]", value: "]"), URL(string: "https://duck.com/?%5D=%5D")!)
        XCTAssertEqual(url.appendingParameter(name: "@", value: "@"), URL(string: "https://duck.com/?%40=%40")!)
        XCTAssertEqual(url.appendingParameter(name: "!", value: "!"), URL(string: "https://duck.com/?%21=%21")!)
        XCTAssertEqual(url.appendingParameter(name: "$", value: "$"), URL(string: "https://duck.com/?%24=%24")!)
        XCTAssertEqual(url.appendingParameter(name: "&", value: "&"), URL(string: "https://duck.com/?%26=%26")!)
        XCTAssertEqual(url.appendingParameter(name: "'", value: "'"), URL(string: "https://duck.com/?%27=%27")!)
        XCTAssertEqual(url.appendingParameter(name: "(", value: "("), URL(string: "https://duck.com/?%28=%28")!)
        XCTAssertEqual(url.appendingParameter(name: ")", value: ")"), URL(string: "https://duck.com/?%29=%29")!)
        XCTAssertEqual(url.appendingParameter(name: "*", value: "*"), URL(string: "https://duck.com/?%2A=%2A")!)
        XCTAssertEqual(url.appendingParameter(name: "+", value: "+"), URL(string: "https://duck.com/?%2B=%2B")!)
        XCTAssertEqual(url.appendingParameter(name: ",", value: ","), URL(string: "https://duck.com/?%2C=%2C")!)
        XCTAssertEqual(url.appendingParameter(name: ";", value: ";"), URL(string: "https://duck.com/?%3B=%3B")!)
        XCTAssertEqual(url.appendingParameter(name: "=", value: "="), URL(string: "https://duck.com/?%3D=%3D")!)
    }

    func testWhenAddParameterIsCalled_ThenItAllowsUnescapedReservedCharactersAsSpecified() {
        let url = URL(string: "https://duck.com/")!

        XCTAssertEqual(
            url.appendingParameter(
                name: "domains",
                value: "test.com,example.com/test,localhost:8000/api",
                allowedReservedCharacters: .init(charactersIn: ",:")
            ),
            URL(string: "https://duck.com/?domains=test.com,example.com%2Ftest,localhost:8000%2Fapi")!
        )
    }

    func testWhenPunycodeUrlIsCalledOnEmptyStringThenUrlIsNotReturned() {
        XCTAssertNil(URL(trimmedAddressBarString: "")?.absoluteString)
    }

    func testWhenPunycodeUrlIsCalledOnQueryThenUrlIsNotReturned() {
        XCTAssertNil(URL(trimmedAddressBarString: " ")?.absoluteString)
    }

    func testWhenPunycodeUrlIsCalledOnQueryWithSpaceThenUrlIsNotReturned() {
        XCTAssertNil(URL(trimmedAddressBarString: "https://www.duckduckgo .com/html?q=search")?.absoluteString)
        XCTAssertNil(URL(trimmedAddressBarString: "https://www.duckduckgo.com/html?q =search")?.absoluteString)
    }

    func testWhenPunycodeUrlIsCalledOnLocalHostnameThenUrlIsNotReturned() {
        XCTAssertNil(URL(trimmedAddressBarString: "💩")?.absoluteString)
    }

    func testWhenDefineSearchRequestIsMadeItIsNotInterpretedAsLocalURL() {
        XCTAssertNil(URL(trimmedAddressBarString: "define:300/spartans")?.absoluteString)
    }

    func testAddressBarURLParsing() {
        struct TestItem {
            let stringValue: String
            let expectedValue: String
            let line: UInt
            init(_ rawValue: String, _ expectedValue: String? = nil, line: UInt = #line) {
                self.stringValue = rawValue
                self.expectedValue = expectedValue ?? rawValue
                self.line = line
            }
            var url: URL? {
                stringValue.decodedURL
            }
        }

        let addresses: [TestItem] = [
            .init("user@somehost.local:9091/index.html"),
            .init("something.local:9100"),
            .init("user@localhost:5000"),
            .init("user:password@localhost:5000"),
            .init("localhost"),
            .init("localhost:5000"),
            .init("sms://+44123123123"),
            .init("mailto:test@example.com"),
            .init("mailto:u%24ser@💩.la?arg=b#1", "mailto:u%24ser@xn--ls8h.la?arg=b%231"),
            .init("62.12.14.111"),
            .init("https://"),
            .init("http://duckduckgo.com"),
            .init("https://duckduckgo.com"),
            .init("https://duckduckgo.com/"),
            .init("duckduckgo.com"),
            .init("duckduckgo.com/html?q=search"),
            .init("www.duckduckgo.com"),
            .init("https://www.duckduckgo.com/html?q=search"),
            .init("https://www.duckduckgo.com/html/?q=search"),
            .init("ftp://www.duckduckgo.com"),
            .init("file:///users/user/Documents/afile"),
        ]

        for item in addresses {
            let address = item.stringValue
            let url = URL(trimmedAddressBarString: address)
            var expectedString = item.expectedValue
            let expectedScheme = address.hasPrefix("mailto:") ? "mailto" : (address.split(separator: "/").first.flatMap {
                $0.hasSuffix(":") ? String($0).dropping(suffix: ":") : nil
            }?.lowercased() ?? "http")
            if !address.hasPrefix(expectedScheme) {
                expectedString = expectedScheme + "://" + address
            }
            XCTAssertEqual(url?.scheme, expectedScheme, line: item.line)
            XCTAssertEqual(url?.absoluteString, expectedString, line: item.line)
        }
    }

    func testWhenURLParametersModifiedWithInvalidCharactersThenParametersArePercentEscaped() {
        XCTAssertEqual(URL(trimmedAddressBarString: "https://www.duckduckgo.com/html?q=a%20search with+space?+and%25plus&ia=calculator")!.absoluteString,
                       "https://www.duckduckgo.com/html?q=a%20search%20with+space?+and%25plus&ia=calculator")
    }

    func testWhenURLWithEmptyQueryIsFixedUpThenQuestionCharIsKept() {
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/?")!.absoluteString,
                       "https://duckduckgo.com/?")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com?")!.absoluteString,
                       "https://duckduckgo.com?")
        XCTAssertEqual(URL(trimmedAddressBarString: "https:/duckduckgo.com/?")!.absoluteString,
                       "https://duckduckgo.com/?")
        XCTAssertEqual(URL(trimmedAddressBarString: "https:/duckduckgo.com?")!.absoluteString,
                       "https://duckduckgo.com?")
    }

    func testWhenURLWithHashIsFixedUpThenHashIsCorrectlyEscaped() {
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/#hash with #")!.absoluteString,
                       "https://duckduckgo.com/#hash%20with%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q=a b#hash with #")!.absoluteString,
                       "https://duckduckgo.com/html?q=a%20b#hash%20with%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html#hash with #")!.absoluteString,
                       "https://duckduckgo.com/html#hash%20with%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q#hash with #")!.absoluteString,
                       "https://duckduckgo.com/html?q#hash%20with%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html?#hash with? #")!.absoluteString,
                       "https://duckduckgo.com/html?#hash%20with?%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q=a b#")!.absoluteString,
                       "https://duckduckgo.com/html?q=a%20b#")
    }

    func testWhenPunycodeUrlIsCalledWithEncodedUrlsThenUrlIsReturned() {
        XCTAssertEqual("http://xn--ls8h.la", "💩.la".decodedURL?.absoluteString)
        XCTAssertEqual("http://xn--ls8h.la/", "💩.la/".decodedURL?.absoluteString)
        XCTAssertEqual("http://82.xn--b1aew.xn--p1ai", "82.мвд.рф".decodedURL?.absoluteString)
        XCTAssertEqual("http://xn--ls8h.la:8080", "http://💩.la:8080".decodedURL?.absoluteString)
        XCTAssertEqual("http://xn--ls8h.la", "http://💩.la".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la", "https://💩.la".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la/", "https://💩.la/".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la/path/to/resource", "https://💩.la/path/to/resource".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la/path/to/resource?query=true", "https://💩.la/path/to/resource?query=true".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la/%F0%9F%92%A9", "https://💩.la/💩".decodedURL?.absoluteString)
    }

    func testWhenParamExistsThengetParameterReturnsCorrectValue() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let expected = "secondValue"
        let actual = url.getParameter(named: "secondParam")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamDoesNotExistThengetParameterIsNil() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let result = url.getParameter(named: "someOtherParam")
        XCTAssertNil(result)
    }

    func testWhenParamExistsThenRemovingReturnUrlWithoutParam() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let expected = URL(string: "http://test.com?secondParam=secondValue")!
        let actual = url.removeParameter(name: "firstParam")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamDoesNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removeParameter(name: "someOtherParam")
        XCTAssertEqual(actual, url)
    }

    func testWhenRemovingAParamThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")!
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")!
        let actual = url.removeParameter(name: "firstParam")
        XCTAssertEqual(actual, expected)
    }

    func testWhenRemovingParamsThenRemovingReturnsUrlWithoutParams() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue&thirdParam=thirdValue")!
        let expected = URL(string: "http://test.com?secondParam=secondValue")!
        let actual = url.removingParameters(named: ["firstParam", "thirdParam"])
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamsDoNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removingParameters(named: ["someParam", "someOtherParam"])
        XCTAssertEqual(actual, url)
    }

    func testWhenEmptyParamArrayIsUsedThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removingParameters(named: [])
        XCTAssertEqual(actual, url)
    }

    func testWhenRemovingParamsThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")!
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")!
        let actual = url.removingParameters(named: ["firstParam"])
        XCTAssertEqual(actual, expected)
    }

    func testWhenNoParamsThenAddingAppendsQuery() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=aValue")!
        let actual = url.appendingParameter(name: "aParam", value: "aValue")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamDoesNotExistThenAddingParamAppendsItToExistingQuery() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&anotherParam=anotherValue")!
        let actual = url.appendingParameter(name: "anotherParam", value: "anotherValue")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamHasInvalidCharactersThenAddingParamAppendsEncodedVersion() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=43%20%2B%205")!
        let actual = url.appendingParameter(name: "aParam", value: "43 + 5")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamExistsThenAddingNewValueAppendsParam() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&firstParam=newValue")!
        let actual = url.appendingParameter(name: "firstParam", value: "newValue")
        XCTAssertEqual(actual, expected)
    }

    func testMatchesComparator() {
        XCTAssertTrue("youtube.com".url!.matches("http://youtube.com".url!))
        XCTAssertTrue("youtube.com/".url!.matches("http://youtube.com".url!))
        XCTAssertTrue("youtube.com".url!.matches("http://youtube.com/".url!))
        XCTAssertTrue("youtube.com/".url!.matches("http://youtube.com/".url!))
        XCTAssertTrue("http://youtube.com/".url!.matches("youtube.com".url!))
        XCTAssertTrue("http://youtube.com".url!.matches("youtube.com/".url!))
        XCTAssertTrue("https://youtube.com/".url!.matches("https://youtube.com".url!))
        XCTAssertTrue("https://youtube.com/#link#1".url!.matches("https://youtube.com#link#1".url!))
        XCTAssertTrue("https://youtube.com/#link#1".url!.matches("https://youtube.com#link#1".url!))
        XCTAssertTrue("https://youtube.com/#link#1".url!.matches("https://youtube.com/#link#1".url!))
        XCTAssertTrue("https://youtube.com#link#1".url!.matches("https://youtube.com/#link#1".url!))

        XCTAssertFalse("youtube.com".url!.matches("https://youtube.com".url!))
        XCTAssertFalse("youtube.com/".url!.matches("https://youtube.com".url!))
        XCTAssertFalse("youtube.com/#link#1".url!.matches("https://youtube.com#link#2".url!))
        XCTAssertFalse("youtube.com/#link#1".url!.matches("https://youtube.com#link".url!))
    }

    func testMatchesProtectionSpace() {
        XCTAssertTrue("youtube.com".url!.matches(URLProtectionSpace(host: "youtube.com", port: 80, protocol: "http", realm: "realm", authenticationMethod: "basic")))
        XCTAssertTrue("http://youtube.com".url!.matches(URLProtectionSpace(host: "youtube.com", port: 80, protocol: "http", realm: "realm", authenticationMethod: "basic")))
        XCTAssertTrue("https://youtube.com:123".url!.matches(URLProtectionSpace(host: "youtube.com", port: 123, protocol: "https", realm: "realm", authenticationMethod: "basic")))

        XCTAssertFalse("https://youtube.com:123".url!.matches(URLProtectionSpace(host: "youtube.com", port: 1234, protocol: "https", realm: "realm", authenticationMethod: "basic")))
        XCTAssertFalse("https://youtube.com:123".url!.matches(URLProtectionSpace(host: "youtube.com", port: 123, protocol: "http", realm: "realm", authenticationMethod: "basic")))
        XCTAssertFalse("https://www.youtube.com:123".url!.matches(URLProtectionSpace(host: "youtube.com", port: 123, protocol: "https", realm: "realm", authenticationMethod: "basic")))
    }

    func testWhenCallQueryItemWithNameAndURLHasQueryItemThenReturnQueryItem() throws {
        // GIVEN
        let url = try XCTUnwrap(URL(string: "www.duckduckgo.com?origin=test"))

        // WHEN
        let result = url.getQueryItem(named: "origin")

        // THEN
        let queryItem = try XCTUnwrap(result)
        XCTAssertEqual(queryItem.name, "origin")
        XCTAssertEqual(queryItem.value, "test")
    }

    func testWhenCallQueryItemWithNameAndURLDoesNotHaveQueryItemThenReturnNil() throws {
        // GIVEN
        let url = try XCTUnwrap(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.getQueryItem(named: "test")

        // THEN
        XCTAssertNil(result)
    }

    func testWhenCallAppendingQueryItemThenReturnURLWithQueryItem() throws {
        // GIVEN
        let url = try XCTUnwrap(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.appending(percentEncodedQueryItem: .init(name: "origin", value: "test"))

        // THEN
        XCTAssertEqual(result.absoluteString, "www.duckduckgo.com?origin=test")
    }

    func testWhenCallAppendingQueryItemsThenReturnURLWithQueryItems() throws {
        // GIVEN
        let queryItems = [URLQueryItem(name: "origin", value: "test"), URLQueryItem(name: "another_item", value: "test_2")]
        let url = try XCTUnwrap(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.appending(percentEncodedQueryItems: queryItems)

        // THEN
        XCTAssertEqual(result.absoluteString, "www.duckduckgo.com?origin=test&another_item=test_2")
    }

    func testWhenCallGetQueryItemsThenReturnQueryItemsForURL() throws {
        // GIVEN
        let url = try XCTUnwrap(URL(string: "www.duckduckgo.com?origin=test&another_item=test_2"))

        // WHEN
        let result = try XCTUnwrap(url.getQueryItems())

        // THEN
        XCTAssertEqual(result.first, .init(name: "origin", value: "test"))
        XCTAssertEqual(result.last, .init(name: "another_item", value: "test_2"))
    }

    func testWhenUserInfoDoesNotContaintPassword_ThenNavigateToSearch() {
        XCTAssertNil(URL(trimmedAddressBarString: "user@domain.com"))
        XCTAssertNil(URL(trimmedAddressBarString: "user: @domain.com"))

        XCTAssertEqual(URL(trimmedAddressBarString: "user:,,@domain.com")?.host, "domain.com")
        XCTAssertEqual(URL(trimmedAddressBarString: "user:pass@domain.com")?.host, "domain.com")
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
}
