//
//  CanonicalURLTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

// swiftlint:disable line_length file_length

import Foundation
import Testing

@testable import Common

/// Pins `URL.canonicalURL()` to the results recorded from the implementation that found the fragment with
/// `String.range(of: "#")` and removed tabs and line breaks character by character, before the fragment position came
/// from Core Foundation's parsed URL.
///
/// The inputs are the Safe Browsing URL canonicalization examples plus corner cases for fragments, control characters,
/// Unicode, hosts, schemes, paths, percent-encoding, queries, relative URLs and sizes around the percent-decoding limit.
/// Each one is created three ways, because the backing store decides where Core Foundation says the fragment starts:
/// `URL(string:)`, `NSURL(string:)` and `CFURLCreateWithBytes`, which is how WebKit creates the URLs it hands to
/// navigation delegates.
///
/// The recorded results are the behavior to keep, not a statement that they match the specification: for example,
/// `www.` is dropped and an IP address is not rewritten to dotted-quad form.
@Suite("URL.canonicalURL() matches the recorded behavior")
struct CanonicalURLTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let input: String
        let expected: String?
        init(_ input: String, _ expected: String?) {
            self.input = input
            self.expected = expected
        }
        var testDescription: String { String(input.prefix(80)) }
    }

    /// The old implementation gave different results depending on how the URL was created.
    struct BackingDependentCase: Sendable, CustomTestStringConvertible {
        let input: String
        let swift: String?
        let ns: String?
        let cf: String?
        init(_ input: String, swift: String?, ns: String?, cf: String?) {
            self.input = input
            self.swift = swift
            self.ns = ns
            self.cf = cf
        }
        var testDescription: String { String(input.prefix(80)) }
    }

    struct RelativeCase: Sendable, CustomTestStringConvertible {
        let relative: String
        let base: String
        let swift: String?
        let ns: String?
        init(_ relative: String, base: String, swift: String?, ns: String?) {
            self.relative = relative
            self.base = base
            self.swift = swift
            self.ns = ns
        }
        var testDescription: String { "\(relative) relative to \(base)" }
    }

    // MARK: - Helpers

    static func cfURL(_ string: String) -> URL? {
        let bytes = Array(string.utf8)
        let created = CFURLCreateWithBytes(kCFAllocatorDefault, bytes, bytes.count, CFStringBuiltInEncodings.UTF8.rawValue, nil)
        return created.map { $0 as URL }
    }

    static func canonical(_ url: URL?) -> String? {
        url?.canonicalURL()?.absoluteString
    }

    // MARK: - Recorded results, the same for every way of creating the URL

    @available(iOS 16, macOS 13, *)
    @Test("canonicalURL — recorded result", .timeLimit(.minutes(1)), arguments: CanonicalURLTests.recorded)
    func recordedResult(_ testCase: Case) {
        #expect(Self.canonical(URL(string: testCase.input)) == testCase.expected, "URL(string:)")
        #expect(Self.canonical(NSURL(string: testCase.input) as URL?) == testCase.expected, "NSURL(string:)")
        #expect(Self.canonical(Self.cfURL(testCase.input)) == testCase.expected, "CFURLCreateWithBytes")
    }

    @available(iOS 16, macOS 13, *)
    @Test("canonicalURL — recorded result that depends on how the URL was created", .timeLimit(.minutes(1)), arguments: CanonicalURLTests.recordedBackingDependent)
    func recordedBackingDependentResult(_ testCase: BackingDependentCase) {
        #expect(Self.canonical(URL(string: testCase.input)) == testCase.swift, "URL(string:)")
        #expect(Self.canonical(NSURL(string: testCase.input) as URL?) == testCase.ns, "NSURL(string:)")
        #expect(Self.canonical(Self.cfURL(testCase.input)) == testCase.cf, "CFURLCreateWithBytes")
    }

    @available(iOS 16, macOS 13, *)
    @Test("canonicalURL — recorded result of a relative URL", .timeLimit(.minutes(1)), arguments: CanonicalURLTests.recordedRelative)
    func recordedRelativeResult(_ testCase: RelativeCase) throws {
        let base = try #require(URL(string: testCase.base))

        #expect(Self.canonical(URL(string: testCase.relative, relativeTo: base)) == testCase.swift, "URL(string:relativeTo:)")
        #expect(Self.canonical(NSURL(string: testCase.relative, relativeTo: base) as URL?) == testCase.ns, "NSURL(string:relativeTo:)")
    }

    // MARK: - Sizes around the percent-decoding limit (8192 bytes) and large fragments

    @available(iOS 16, macOS 13, *)
    @Test("canonicalURL — recorded result for long URLs", .timeLimit(.minutes(1)))
    func recordedResultForLongURLs() {
        let host = "http://e.com/"
        let cases: [Case] = [
            // Below the limit the escapes are decoded; above it they are left alone.
            Case(host + String(repeating: "%41", count: 2_500), host + String(repeating: "a", count: 2_500)),
            Case(host + String(repeating: "%41", count: 3_000), host + String(repeating: "%41", count: 3_000)),
            Case(host + String(repeating: "a", count: 8_000) + "%41", host + String(repeating: "a", count: 8_001)),
            Case(host + String(repeating: "a", count: 9_000) + "%41", host + String(repeating: "a", count: 9_000) + "%41"),
            // The fragment is dropped whatever its size.
            Case("http://e.com/p?" + String(repeating: "a=1&", count: 3_000) + "#" + String(repeating: "f", count: 5_000),
                 "http://e.com/p?" + String(repeating: "a=1&", count: 3_000)),
            Case("http://e.com/p#" + String(repeating: "f", count: 100_000), "http://e.com/p"),
        ]

        for testCase in cases {
            #expect(Self.canonical(URL(string: testCase.input)) == testCase.expected, "URL(string:) \(testCase.testDescription)")
            #expect(Self.canonical(NSURL(string: testCase.input) as URL?) == testCase.expected, "NSURL(string:) \(testCase.testDescription)")
            #expect(Self.canonical(Self.cfURL(testCase.input)) == testCase.expected, "CFURLCreateWithBytes \(testCase.testDescription)")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("canonicalURL — keeps the query and drops the fragment of a multi-megabyte URL", .timeLimit(.minutes(1)), arguments: [false, true])
    func largeURL(hasFragment: Bool) throws {
        let query = String(repeating: "a=1&", count: 500_000)
        let fragment = hasFragment ? "#" + String(repeating: "f", count: 100_000) : ""
        let input = "https://example.com/path?" + query + fragment
        let expected = "https://example.com/path?" + query

        #expect(Self.canonical(NSURL(string: input) as URL?) == expected)
        #expect(Self.canonical(Self.cfURL(input)) == expected)
    }

    // MARK: - A URL never contains a raw tab, CR or LF

    @available(iOS 16, macOS 13, *)
    @Test("URL never contains a raw tab, CR or LF, so canonicalization has nothing to strip", .timeLimit(.minutes(1)), arguments: [
        "https://example.com/a\tb",
        "https://example.com/a\nb",
        "https://example.com/a\rb",
        "https://example.com/a\r\nb",
        "https://example.com/p?q=\t1\r\n2",
        "https://example.com/p#fr\tag\n",
        "https://example.com/\t\n\r#\t\n\r",
    ])
    func urlNeverContainsRawTabOrLineBreak(string: String) {
        let controlCharacters = CharacterSet(charactersIn: "\t\r\n")

        for url in [URL(string: string), NSURL(string: string) as URL?, Self.cfURL(string)].compactMap({ $0 }) {
            #expect(url.absoluteString.rangeOfCharacter(from: controlCharacters) == nil)
            #expect(url.canonicalURL()?.absoluteString.rangeOfCharacter(from: controlCharacters) == nil)
        }
    }

    // MARK: - Recorded data

    static let recorded: [Case] = [
        Case("http://host/%25%32%35", "http://host/%25"),
        Case("http://host/%25%32%35%25%32%35", "http://host/%25%25"),
        Case("http://host/%2525252525252525", "http://host/%25"),
        Case("http://host/asdf%25%32%35asd", "http://host/asdf%25asd"),
        Case("http://www.google.com/", "http://google.com/"),
        Case("http://%31%36%38%2e%31%38%38%2e%39%39%2e%32%36/%2E%73%65%63%75%72%65/%77%77%77%2E%65%62%61%79%2E%63%6F%6D/", "http://168.188.99.26/.secure/www.ebay.com"),
        Case("http://195.127.0.11/uploads/%20%20%20%20/.verify/.eBaysecure=updateuserdataxplimnbqmn-xplmvalidateinfoswqpcmlx=hgplmcx/", "http://195.127.0.11/uploads/%20%20%20%20/.verify/.ebaysecure=updateuserdataxplimnbqmn-xplmvalidateinfoswqpcmlx=hgplmcx"),
        Case("http://host%23.com/%257Ea%2521b%2540c%2523d%2524e%25f%255E00%252611%252A22%252833%252944_55%252B", nil),
        Case("http://3279880203/blah", "http://3279880203/blah"),
        Case("http://www.google.com/blah/..", "http://google.com/blah/.."),
        Case("www.google.com/", "www.google.com"),
        Case("www.google.com", "www.google.com"),
        Case("http://www.evil.com/blah#frag", "http://evil.com/blah"),
        Case("http://www.GOOgle.com/", "http://google.com/"),
        Case("http://www.google.com.../", "http://google.com.../"),
        Case("http://www.google.com/foo\tbar\rbaz\n2", "http://google.com/foo%09bar%0Dbaz%0A2"),
        Case("http://www.google.com/q?", "http://google.com/q?"),
        Case("http://www.google.com/q?r?", "http://google.com/q?r?"),
        Case("http://www.google.com/q?r?s", "http://google.com/q?r?s"),
        Case("http://evil.com/foo#bar#baz", "http://evil.com/foo"),
        Case("http://evil.com/foo;", "http://evil.com/foo;"),
        Case("http://evil.com/foo?bar;", "http://evil.com/foo?bar;"),
        Case("http://\u{01}.com/", nil),
        Case("http://notrailingslash.com", nil),
        Case("http://www.gotaport.com:1234/", "http://gotaport.com:1234/"),
        Case("  http://www.google.com/  ", nil),
        Case("http:// leadingspace.com/", nil),
        Case("http://%20leadingspace.com/", nil),
        Case("%20leadingspace.com/", "%20leadingspace.com"),
        Case("https://www.securesite.com/", "https://securesite.com/"),
        Case("http://host.com/ab%23cd", "http://host.com/ab#cd"),
        Case("http://host.com//twoslashes?more//slashes", "http://host.com/twoslashes?more/slashes"),
        Case("http://e.com/#", "http://e.com/"),
        Case("http://e.com#", nil),
        Case("http://e.com/?#", "http://e.com/?"),
        Case("http://e.com/p?q=1#frag?x=y", "http://e.com/p?q=1"),
        Case("http://e.com/p#%23", "http://e.com/p"),
        Case("http://e.com/p%23#x", "http://e.com/p#"),
        Case("http://e.com/#/a/../b", "http://e.com/"),
        Case("http://e.com/p?q=%23#", "http://e.com/p?q=#"),
        Case("http://e.com/p#é日本", "http://e.com/p"),
        Case("http://e.com/#a#b#c", "http://e.com/"),
        Case("http://e.com/p?q=1#frag#", "http://e.com/p?q=1"),
        Case("http://e.com/p#frag%23x", "http://e.com/p"),
        Case("http://e.com/?q=#", "http://e.com/?q="),
        Case("http://e.com/p/#/", "http://e.com/p"),
        Case("#", nil),
        Case("http://#", nil),
        Case("http:///#", "http:///"),
        Case("http://e.com/a%09b", "http://e.com/a%09b"),
        Case("http://e.com/a%0Ab", "http://e.com/a%0Ab"),
        Case("http://e.com/a%0D%0Ab", "http://e.com/a%0D%0Ab"),
        Case("http://e.com/a\tb", "http://e.com/a%09b"),
        Case("http://e.com/a\nb", "http://e.com/a%0Ab"),
        Case("http://e.com/a\r\nb", "http://e.com/a%0D%0Ab"),
        Case("http://e.com/p?q=\t1\r\n2", "http://e.com/p?q=%091%0D%0A2"),
        Case("http://e.com/p#fr\tag\n", "http://e.com/p"),
        Case("http://e.com/a\tb#f", "http://e.com/a%09b"),
        Case("http://e.com/\t", "http://e.com/%09"),
        Case("http://e.com/%09#f", "http://e.com/%09"),
        Case("http://e.com/\u{0B}\u{0C}", "http://e.com/%0B%0C"),
        Case("http://e.com/é", "http://e.com/%C3%A9"),
        Case("http://пример.рф/p", "http://xn--e1afmkfd.xn--p1ai/p"),
        Case("http://пример.рф/p#f", "http://xn--e1afmkfd.xn--p1ai/p"),
        Case("http://e.com/?q=ü", "http://e.com/?q=%C3%BC"),
        Case("http://e.com/日本#日本", "http://e.com/%E6%97%A5%E6%9C%AC"),
        Case("http://e.com/é#日本", "http://e.com/%C3%A9"),
        Case("http://e.com/%C3%A9#x", "http://e.com/%C3%A9"),
        Case("http://e.com/👨‍👩‍👧‍👦#f", "http://e.com/%F0%9F%91%A8%E2%80%8D%F0%9F%91%A9%E2%80%8D%F0%9F%91%A7%E2%80%8D%F0%9F%91%A6"),
        Case("http://EXAMPLE.com/É", "http://example.com/%C3%A9"),
        Case("http://e.com/‮x#y", "http://e.com/%E2%80%AEx"),
        Case("http://ex́ample.com/p#f", "http://xn--example-uge.com/p"),
        Case("http://WWW.EXAMPLE.COM./", "http://example.com./"),
        Case("http://.example.com/", "http://.example.com/"),
        Case("http://a..b.com/", "http://a..b.com/"),
        Case("http://1.2.3/", "http://1.2.3/"),
        Case("http://0x7f.1/", "http://0x7f.1/"),
        Case("http://017700000001/", "http://017700000001/"),
        Case("http://[::1]/p#f", "http://[::1]/p"),
        Case("http://[2001:db8::1]:8080/p#f", "http://[2001:db8::1]:8080/p"),
        Case("http://user:pass@e.com/p#f", "http://user:pass@e.com/p"),
        Case("http://user@e.com/", "http://user@e.com/"),
        Case("http://e.com:80/p#f", "http://e.com:80/p"),
        Case("http://e.com:8080/p", "http://e.com:8080/p"),
        Case("http://a.b.c.d.e.f.g.h.com/", "http://a.b.c.d.e.f.g.h.com/"),
        Case("http://www.www.e.com/", "http://www.e.com/"),
        Case("http://WWW.e.com/#f", "http://e.com/"),
        Case("http://e.com:/p", "http://e.com:/p"),
        Case("http://e.com:0/p", "http://e.com:0/p"),
        Case("http://1.1.1.1/#f", "http://1.1.1.1/"),
        Case("http://256.1.1.1/", "http://256.1.1.1/"),
        Case("http://localhost/#f", "http://localhost/"),
        Case("http://e/", "http://e/"),
        Case("http://-e-.com/", "http://-e-.com/"),
        Case("ftp://e.com/p#f", "ftp://e.com/p"),
        Case("file:///a/b#c", "file:///a/b"),
        Case("file://host/a/b#c", "file://host/a/b"),
        Case("about:blank", "about:blank"),
        Case("data:text/html,a%23b", "data:text/html,a#b"),
        Case("duck://player/abc#t", "duck://player/abc"),
        Case("HTTP://E.COM/P#F", "http://e.com/p"),
        Case("https://e.com", nil),
        Case("custom-scheme://host/path#f", "custom-scheme://host/path"),
        Case("http://e.com/a/./b/../c", "http://e.com/a/c"),
        Case("http://e.com/../../a", "http:/a"),
        Case("http://e.com/./", "http://e.com/."),
        Case("http://e.com//", "http://e.com/"),
        Case("http://e.com/a//b///c", "http://e.com/a/b/c"),
        Case("http://e.com/%2e%2e/a", nil),
        Case("http://e.com/%252e%252e/a", nil),
        Case("http://e.com/a/%2E/b", "http://e.com/a/b"),
        Case("http://e.com/a/b/../../..", "http://e.com/.."),
        Case("http://e.com/a/b/../..", "http://e.com/a/.."),
        Case("http://e.com/a/.", "http://e.com/a/."),
        Case("http://e.com/a/..", "http://e.com/a/.."),
        Case("http://e.com/.../a", "http://e.com/.../a"),
        Case("http://e.com/a/./././b", "http://e.com/a/./b"),
        Case("http://e.com/a/%2e/../b#f", "http://e.com/b"),
        Case("http://e.com/a/b/", "http://e.com/a/b"),
        Case("http://e.com/a/b///", "http://e.com/a/b"),
        Case("http://e.com/;/a", "http://e.com/;/a"),
        Case("http://e.com/a;b/c", "http://e.com/a;b/c"),
        Case("http://e.com/%", "http://e.com/%25"),
        Case("http://e.com/%zz", "http://e.com/%25zz"),
        Case("http://e.com/%2", "http://e.com/%252"),
        Case("http://e.com/%25", "http://e.com/%25"),
        Case("http://e.com/%2525", "http://e.com/%25"),
        Case("http://e.com/%C3%A9", "http://e.com/%C3%A9"),
        Case("http://e.com/%FF", nil),
        Case("http://e.com/%00", "http://e.com/%00"),
        Case("http://e.com/%7E", "http://e.com/~"),
        Case("http://e.com/%2F", "http://e.com/"),
        Case("http://e.com/a%2Fb", "http://e.com/a/b"),
        Case("http://e.com/%252F%252F", "http://e.com/"),
        Case("http://e.com/?q=%26&r=%3D", "http://e.com/?q=&&r=="),
        Case("http://e.com/path?%61=%62", "http://e.com/path?a=b"),
        Case("http://e.com/%u0041", "http://e.com/%25u0041"),
        Case("http://e.com/%2525252525252525252525252525252525#f", "http://e.com/%25"),
        Case("http://e.com/?a=1&b=2", "http://e.com/?a=1&b=2"),
        Case("http://e.com/?", "http://e.com/?"),
        Case("http://e.com/??", "http://e.com/??"),
        Case("http://e.com/?a=1#", "http://e.com/?a=1"),
        Case("http://e.com/p?a=b?c=d", "http://e.com/p?a=b?c=d"),
        Case("http://e.com/p?a=%3Fb", "http://e.com/p?a=?b"),
        Case("http://e.com/p?a=b//c", "http://e.com/p?a=b/c"),
        Case("http://e.com/p?a=../b", "http://e.com/p?a=../b"),
        Case("http://e.com/p?a=./b", "http://e.com/p?a=./b"),
        Case("http://e.com/?A=B", "http://e.com/?a=b"),
        Case("http://e.com/p?a=b%20c", "http://e.com/p?a=b%20c"),
    ]

    static let recordedBackingDependent: [BackingDependentCase] = [
        BackingDependentCase("http://host/%%%25%32%35asd%%",
                             swift: "http://host/%25%25%2525%2532%2535asd%25%25",
                             ns: "http://host/%25%25%2525%2532%2535asd%25%25",
                             cf: "http://host/%25%25%2525asd%25%25"),
        BackingDependentCase("mailto:a@b.c#x",
                             swift: "mailto:a@b.c",
                             ns: "mailto:a@b.c#x",
                             cf: "mailto:a@b.c#x"),
        BackingDependentCase("about:blank#x",
                             swift: "about:blank",
                             ns: "about:blank#x",
                             cf: "about:blank#x"),
        BackingDependentCase("data:text/html,a#b",
                             swift: "data:text/html,a",
                             ns: "data:text/html,a#b",
                             cf: "data:text/html,a#b"),
        BackingDependentCase("javascript:void(0)#z",
                             swift: "javascript:void(0)",
                             ns: "javascript:void(0)#z",
                             cf: "javascript:void(0)#z"),
        BackingDependentCase("blob:https://e.com/uuid#f",
                             swift: "blob:https://e.com/uuid",
                             ns: "blob:https://e.com/uuid#f",
                             cf: "blob:https://e.com/uuid#f"),
        BackingDependentCase("tel:+123#x",
                             swift: "tel:+123",
                             ns: "tel:+123#x",
                             cf: "tel:+123#x"),
        BackingDependentCase("http://e.com/%%41",
                             swift: "http://e.com/%25%2541",
                             ns: "http://e.com/%25%2541",
                             cf: "http://e.com/%25a"),
        BackingDependentCase("http://e.com/%41%",
                             swift: "http://e.com/%2541%25",
                             ns: "http://e.com/%2541%25",
                             cf: "http://e.com/a%25"),
    ]

    static let recordedRelative: [RelativeCase] = [
        RelativeCase("/p?q=1#f", base: "https://www.example.com", swift: "https://example.com/p?q=1", ns: "https://example.com/p?q=1"),
        RelativeCase("p#f", base: "https://example.com/a/b", swift: "https://example.com/a/p", ns: "https://example.com/a/p"),
        RelativeCase("#f", base: "https://example.com/a?b", swift: "https://example.com/a?b", ns: "https://example.com/a?b"),
        RelativeCase("//other.com/x#f", base: "https://example.com", swift: "https://other.com/x", ns: "https://other.com/x"),
        RelativeCase("../up#f", base: "https://example.com/a/b/c", swift: "https://example.com/a/up", ns: "https://example.com/a/up"),
        RelativeCase("?q#f", base: "https://example.com/p", swift: "https://example.com/p?q", ns: "https://example.com/p?q"),
        RelativeCase("", base: "https://example.com/p#old", swift: nil, ns: "https://example.com/p"),
        RelativeCase("/a/./b/../c#f", base: "https://EXAMPLE.com", swift: "https://example.com/a/c", ns: "https://example.com/a/c"),
        RelativeCase("/p%23x#f", base: "https://example.com", swift: "https://example.com/p#x", ns: "https://example.com/p#x"),
        RelativeCase("/é#日本", base: "https://example.com", swift: "https://example.com/%C3%A9", ns: "https://example.com/%C3%A9"),
        RelativeCase("/a\tb#f", base: "https://example.com", swift: "https://example.com/a%09b", ns: "https://example.com/a%09b"),
        RelativeCase("#", base: "https://example.com/p", swift: "https://example.com/p", ns: "https://example.com/p"),
    ]

}
