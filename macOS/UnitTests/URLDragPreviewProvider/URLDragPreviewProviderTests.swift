//
//  URLDragPreviewProviderTests.swift
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

import AppKit
import Foundation
import SnapshotTestingSupport
import Testing

@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("URL Drag Preview Provider Tests", .disabled("Snapshot testing is opt-in until the sync automations land"))
final class URLDragPreviewProviderTests {

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testURLPreviewWithFavicon() {
        let provider = URLDragPreviewProvider(url: URL(string: "https://duckduckgo.com")!, favicon: .homeFavicon)
        assertImageSnapshot(matching: provider.createPreview(), size: .intrinsicContentSize)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testURLPreviewWithoutFavicon() {
        let provider = URLDragPreviewProvider(url: URL(string: "https://duckduckgo.com")!, favicon: nil)
        assertImageSnapshot(matching: provider.createPreview(), size: .intrinsicContentSize)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testURLPreviewWithCustomColors() {
        let provider = URLDragPreviewProvider(
            url: URL(string: "https://duckduckgo.com")!,
            favicon: .homeFavicon,
            backgroundColor: .button,
            textColor: .textColor
        )
        assertImageSnapshot(matching: provider.createPreview(), size: .intrinsicContentSize)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testURLPreviewWithCustomWidth() {
        let provider = URLDragPreviewProvider(
            url: URL(string: "https://duckduckgo.com")!,
            favicon: .homeFavicon,
            width: 300
        )
        assertImageSnapshot(matching: provider.createPreview(), size: .intrinsicContentSize)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testURLPreviewWithCustomWidthAndWithoutFavicon() {
        let provider = URLDragPreviewProvider(url: URL(string: "https://duckduckgo.com")!, favicon: nil, width: 300)
        assertImageSnapshot(matching: provider.createPreview(), size: .intrinsicContentSize)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testURLPreviewWithLongURL() {
        let provider = URLDragPreviewProvider(
            url: URL(string: "https://very-long-domain-name-that-should-be-truncated.com/path/to/some/very/long/resource")!,
            favicon: .homeFavicon
        )
        assertImageSnapshot(matching: provider.createPreview(), size: .intrinsicContentSize)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testTextPreviewWithTextOnly() {
        let provider = URLDragPreviewProvider(text: "Custom Text Only Preview", favicon: nil)
        assertImageSnapshot(matching: provider.createPreview(), size: .intrinsicContentSize)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testTextPreviewWithFavicon() {
        let provider = URLDragPreviewProvider(text: "Custom Text Only Preview", favicon: .homeFavicon)
        assertImageSnapshot(matching: provider.createPreview(), size: .intrinsicContentSize)
    }

}
