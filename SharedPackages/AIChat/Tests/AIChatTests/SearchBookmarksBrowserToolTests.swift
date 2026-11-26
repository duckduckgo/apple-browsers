//
//  SearchBookmarksBrowserToolTests.swift
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

import Foundation
import Testing
import AIChat

@MainActor
struct SearchBookmarksBrowserToolTests {
    private let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func stopsReadingAfterTheFirstMatchWhenLimitIsOne() async {
        var openedArchive = false
        let tool = SearchBookmarksBrowserTool { search, _ in
            search.matches(in: ["Osaka", "Kyoto", "Archive"]) { node in
                guard node == "Archive" else { return nil }
                return (node, {
                    openedArchive = true
                    return ["Kyoto Archive"]
                })
            } bookmark: { node in
                (node, URL(string: "https://example.com")!)
            }
        }

        let result = await tool.execute(arguments: ["query": "KYOTO", "limit": 1], context: context)

        #expect(result == .success(["results": [["title": "Kyoto", "url": "https://example.com", "folder": []]]]))
        #expect(!openedArchive)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func missingNestedFolderDoesNotReadUnrelatedFolderContents() async {
        var openedArchive = false
        let tool = SearchBookmarksBrowserTool { search, _ in
            search.matches(in: ["Travel", "Archive"]) { node in
                switch node {
                case "Travel":
                    return (node, { ["Kyoto"] })
                case "Archive":
                    return (node, {
                        openedArchive = true
                        return ["Osaka"]
                    })
                default:
                    return nil
                }
            } bookmark: { node in
                (node, URL(string: "https://example.com")!)
            }
        }

        let result = await tool.execute(arguments: ["folder": ["Travel", "Missing"]], context: context)

        #expect(result == .success(["results": []]))
        #expect(!openedArchive)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringSearchDiscardsMatches() async {
        let tool = SearchBookmarksBrowserTool { search, _ in
            let matches = search.matches(in: ["Kyoto"], folder: { _ in nil }, bookmark: { node in
                (node, URL(string: "https://en.wikipedia.org/wiki/Kyoto")!)
            })
            withUnsafeCurrentTask { $0?.cancel() }
            return matches
        }

        let call = Task { await tool.execute(arguments: [:], context: context) }

        #expect(await call.value == .failure(.cancelled))
    }
}
