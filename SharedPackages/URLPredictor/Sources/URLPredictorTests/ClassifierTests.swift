//
//  ClassifierTests.swift
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

import Foundation
import Testing
@testable import URLPredictor

struct ClassifierTests {

    @Test("classifies non-URL as search phrase")
    func classifiesInvalidURLAsSearchPhrase() async throws {
        #expect(try Classifier.classify(input: "one two three") == .search(query: "one two three"))
    }

    @Test("classifies single-slash scheme URL as URL")
    func classifiesSingleSlashSchemeURLAsURL() async throws {
        #expect(try Classifier.classify(input: "http:/example.com") == .navigate(url: URL(string: "http://example.com/")!))
    }

    @Test("Creating URLs with international characters")
    func creatingURLsWithInternationalCharacters() throws {
        // URL with international characters in domain
        let urlWithInternationalDomain = try #require(Classifier.classify(input: "https://例子.测试").url)
        #expect(urlWithInternationalDomain.host == "xn--fsqu00a.xn--0zwm56d")
        #expect(urlWithInternationalDomain.absoluteString == "https://xn--fsqu00a.xn--0zwm56d/")

        // URL with international characters in path
        let urlWithInternationalPath = try #require(Classifier.classify(input: "https://example.com/пример/测试").url)
        #expect(urlWithInternationalPath.absoluteString == "https://example.com/%D0%BF%D1%80%D0%B8%D0%BC%D0%B5%D1%80/%E6%B5%8B%E8%AF%95")
    }

    // swiftlint:disable:next identifier_name
    static let makeURL_from_addressBarString_args: [(String, Classifier.Decision, Int)] = [
        ("regular-domain.com/path/to/directory/", .navigate(url: URL(string: "http://regular-domain.com/path/to/directory/")!), #line),
        ("regular-domain.com", .navigate(url: URL(string: "http://regular-domain.com/")!), #line),
        ("regular-domain.com/", .navigate(url: URL(string: "http://regular-domain.com/")!), #line),
        ("regular-domain.com/filename", .navigate(url: URL(string: "http://regular-domain.com/filename")!), #line),
        ("regular-domain.com/filename?a=b&b=c", .navigate(url: URL(string: "http://regular-domain.com/filename?a=b&b=c")!), #line),
        ("regular-domain.com/filename/?a=b&b=c", .navigate(url: URL(string: "http://regular-domain.com/filename/?a=b&b=c")!), #line),
        ("http://regular-domain.com?a=b&b=c", .navigate(url: URL(string: "http://regular-domain.com/?a=b&b=c")!), #line),
        ("http://regular-domain.com/?a=b&b=c", .navigate(url: URL(string: "http://regular-domain.com/?a=b&b=c")!), #line),
        ("https://hexfiend.com/file?q=a", .navigate(url: URL(string: "https://hexfiend.com/file?q=a")!), #line),
        ("https://hexfiend.com/file/?q=a", .navigate(url: URL(string: "https://hexfiend.com/file/?q=a")!), #line),
        ("https://hexfiend.com/?q=a", .navigate(url: URL(string: "https://hexfiend.com/?q=a")!), #line),
        ("https://hexfiend.com?q=a", .navigate(url: URL(string: "https://hexfiend.com/?q=a")!), #line),
        ("regular-domain.com/path/to/file ", .navigate(url: URL(string: "http://regular-domain.com/path/to/file")!), #line),
        ("search string with spaces", .search(query: "search string with spaces"), #line),
        ("https://duckduckgo.com/?q=search string with spaces&arg 2=val 2", .navigate(url: URL(string: "https://duckduckgo.com/?q=search%20string%20with%20spaces&arg%202=val%202")!), #line),
        ("https://duckduckgo.com/?q=search+string+with+spaces", .navigate(url: URL(string: "https://duckduckgo.com/?q=search+string+with+spaces")!), #line),
        ("https://screwjankgames.github.io/engine programming/2020/09/24/writing-your.html", .navigate(url: URL(string: "https://screwjankgames.github.io/engine%20programming/2020/09/24/writing-your.html")!), #line),
        ("define: foo", .search(query: "define: foo"), #line),
        ("   http://example.com\n", .navigate(url: URL(string: "http://example.com/")!), #line),
        (" duckduckgo.com", .navigate(url: URL(string: "http://duckduckgo.com/")!), #line),
        (" duck duck go.c ", .search(query: "duck duck go.c"), #line),
        ("localhost ", .navigate(url: URL(string: "http://localhost/")!), #line),
        ("local ", .search(query: "local"), #line),
        ("test string with spaces", .search(query: "test string with spaces"), #line),
        ("http://💩.la:8080 ", .navigate(url: URL(string: "http://xn--ls8h.la:8080/")!), #line),
        ("http:// 💩.la:8080 ", .search(query: "http:// 💩.la:8080"), #line),
        ("https://xn--ls8h.la/path/to/resource", .navigate(url: URL(string: "https://xn--ls8h.la/path/to/resource")!), #line),
        ("16385-12228.72", .search(query: "16385-12228.72"), #line),
        ("user@localhost", .search(query: "user@localhost"), #line),
        ("http://user@domain.com", .navigate(url: URL(string: "http://user@domain.com/")!), #line),
        ("http://user: @domain.com", .navigate(url: URL(string: "http://user:%20@domain.com/")!), #line),
        ("http://user:,,@domain.com", .navigate(url: URL(string: "http://user:,,@domain.com/")!), #line),
        ("http://user:pass@domain.com", .navigate(url: URL(string: "http://user:pass@domain.com/")!), #line),
        ("http://user name:pass word@domain.com/folder name/file name/", .navigate(url: URL(string: "http://user%20name:pass%20word@domain.com/folder%20name/file%20name/")!), #line),
        ("1+(3+4*2)", .search(query: "1+(3+4*2)"), #line),
        ("localdomain", .search(query: "localdomain"), #line),
        ("1.4/3.4", .search(query: "1.4/3.4"), #line),
        ("user@domain.com", .search(query: "user@domain.com"), #line),
        // different from macOS
        ("http://user:@domain.com", .navigate(url: URL(string: "http://user@domain.com/")!), #line), // on macOS retains the :
        ("test://hello/", .search(query: "test://hello/"), #line), // on macOS is .navigate(url: URL(string: "test://hello/")!)
    ]
    @Test("Creating URLs from address bar strings", arguments: makeURL_from_addressBarString_args)
    func makeURL_from_addressBarString(string: String, expectation: Classifier.Decision, line: Int) throws {
        let decision = try Classifier.classify(input: string)
        #expect(decision == expectation, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    // swiftlint:disable:next identifier_name
    static let windows_tests_args: [(String, Classifier.Decision, Int)] = [
        ("apple.com/mac/", .navigate(url: URL(string: "http://apple.com/mac/")!), #line),
        ("duckduckgo.com", .navigate(url: URL(string: "http://duckduckgo.com/")!), #line),
        ("duckduckgo", .search(query: "duckduckgo"), #line),
        ("www.duckduckgo.com", .navigate(url: URL(string: "http://www.duckduckgo.com/")!), #line),
        ("http://www.duckduckgo.com", .navigate(url: URL(string: "http://www.duckduckgo.com/")!), #line),
        ("https://www.duckduckgo.com", .navigate(url: URL(string: "https://www.duckduckgo.com/")!), #line),
        ("127.0.0.1", .navigate(url: URL(string: "http://127.0.0.1/")!), #line),
        ("http://127.0.0.1", .navigate(url: URL(string: "http://127.0.0.1/")!), #line),
        ("stuff.stor", .navigate(url: URL(string: "http://stuff.stor/")!), #line),
        ("https://stuff.stor", .navigate(url: URL(string: "https://stuff.stor/")!), #line),
        ("stuff.store", .navigate(url: URL(string: "http://stuff.store/")!), #line),
        ("windows.applicationmodel.store.dll", .navigate(url: URL(string: "http://windows.applicationmodel.store.dll/")!), #line),
        ("1.2.7", .search(query: "1.2.7"), #line),
        ("http://1.2.7", .navigate(url: URL(string: "http://1.2.0.7/")!), #line),
        ("1.2", .search(query: "1.2"), #line),
        ("user:pass@domain.com", .navigate(url: URL(string: "http://user:pass@domain.com/")!), #line),
        ("user: @domain.com", .search(query: "user: @domain.com"), #line),
        ("user:,,@domain.com", .navigate(url: URL(string: "http://user:,,@domain.com/")!), #line),
        ("user:::@domain.com", .navigate(url: URL(string: "http://user:%3A%3A@domain.com/")!), #line),
        ("https://user@domain.com", .navigate(url: URL(string: "https://user@domain.com/")!), #line),
        ("https://user:pass@domain.com", .navigate(url: URL(string: "https://user:pass@domain.com/")!), #line),
        ("https://user: @domain.com", .navigate(url: URL(string: "https://user: @domain.com/")!), #line),
        ("https://user:,,@domain.com", .navigate(url: URL(string: "https://user:,,@domain.com/")!), #line),
        ("https://user:::@domain.com", .navigate(url: URL(string: "https://user:%3A%3A@domain.com/")!), #line),
        ("user@domain.com", .search(query: "user@domain.com"), #line),
    ]
    @Test("Creating URLs from address bar strings - Windows tests", arguments: windows_tests_args)
    func makeURL_from_addressBarString_windowsTests(string: String, expectation: Classifier.Decision, line: Int) throws {
        let decision = try Classifier.classify(input: string)
        #expect(decision == expectation, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    // swiftlint:disable:next identifier_name
    static let whenOneSlashIsMissingAfterHypertextScheme_ThenItShouldBeAdded_args: [(String, Classifier.Decision, Int)] = [
        ("http:/duckduckgo.com", .navigate(url: URL(string: "http://duckduckgo.com/")!), #line),
        ("http://duckduckgo.com", .navigate(url: URL(string: "http://duckduckgo.com/")!), #line),
        ("https:/duckduckgo.com", .navigate(url: URL(string: "https://duckduckgo.com/")!), #line),
        ("https://duckduckgo.com", .navigate(url: URL(string: "https://duckduckgo.com/")!), #line),
        ("file:/Users/user/file.txt", .navigate(url: URL(string: "file:///Users/user/file.txt")!), #line),
        ("file://domain/file.txt", .navigate(url: URL(string: "file://domain/file.txt")!), #line),
        ("file:///Users/user/file.txt", .navigate(url: URL(string: "file:///Users/user/file.txt")!), #line),
    ]
    @Test("Adding missing slash after hypertext scheme", arguments: whenOneSlashIsMissingAfterHypertextScheme_ThenItShouldBeAdded_args)
    func whenOneSlashIsMissingAfterHypertextScheme_ThenItShouldBeAdded(string: String, expectation: Classifier.Decision, line: Int) throws {
        let decision = try Classifier.classify(input: string)
        #expect(decision == expectation, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }
}
