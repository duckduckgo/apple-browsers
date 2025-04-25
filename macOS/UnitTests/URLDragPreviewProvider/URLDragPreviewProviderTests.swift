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

import Foundation
import SnapshotTesting
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class URLDragPreviewProviderTests: XCTestCase {

    private var snapshotWindow: SnapshotWindow!

    override func tearDown() {
        snapshotWindow = nil
        NSApp.appearance = nil
    }

    func snapshot(from provider: URLDragPreviewProvider) -> NSView {
        let preview = provider.createPreview()
        // render with scale factor 1.0
        snapshotWindow = SnapshotWindow(contentRect: preview.bounds, styleMask: [], backing: .buffered, defer: false)
        snapshotWindow.contentView = preview
        return preview
    }

    // MARK: - Tests

    func testURLPreviewWithFavicon() {
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = .init(named: appearanceName)!
            let provider = URLDragPreviewProvider(url: URL(string: "https://duckduckgo.com")!, favicon: .homeFavicon)
            let preview = snapshot(from: provider)

            assertSnapshot(of: preview, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
        }
    }

    func testURLPreviewWithoutFavicon() {
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = .init(named: appearanceName)!
            let provider = URLDragPreviewProvider(url: URL(string: "https://duckduckgo.com")!, favicon: nil)
            let preview = snapshot(from: provider)

            assertSnapshot(of: preview, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
        }
    }

    func testURLPreviewWithCustomColors() {
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = .init(named: appearanceName)!
            let provider = URLDragPreviewProvider(
                url: URL(string: "https://duckduckgo.com")!,
                favicon: .homeFavicon,
                backgroundColor: .button,
                textColor: .textColor
            )
            let preview = snapshot(from: provider)

            assertSnapshot(of: preview, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
        }
    }

    func testURLPreviewWithCustomWidth() {
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = .init(named: appearanceName)!
            let provider = URLDragPreviewProvider(
                url: URL(string: "https://duckduckgo.com")!,
                favicon: .homeFavicon,
                width: 300
            )
            let preview = snapshot(from: provider)

            assertSnapshot(of: preview, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
        }
    }

    func testURLPreviewWithCustomWidthAndWithoutFavicon() {
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = .init(named: appearanceName)!
            let provider = URLDragPreviewProvider(url: URL(string: "https://duckduckgo.com")!, favicon: nil, width: 300)
            let preview = snapshot(from: provider)

            assertSnapshot(of: preview, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
        }
    }

    func testURLPreviewWithLongURL() {
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = .init(named: appearanceName)!
            let provider = URLDragPreviewProvider(
                url: URL(string: "https://very-long-domain-name-that-should-be-truncated.com/path/to/some/very/long/resource")!,
                favicon: .homeFavicon
            )
            let preview = snapshot(from: provider)

            assertSnapshot(of: preview, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
        }
    }

    func testTextPreviewWithTextOnly() {
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = .init(named: appearanceName)!
            let provider = URLDragPreviewProvider(
                text: "Custom Text Only Preview",
                favicon: nil
            )
            let preview = snapshot(from: provider)

            assertSnapshot(of: preview, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
        }
    }

    func testTextPreviewWithFavicon() {
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = .init(named: appearanceName)!
            let provider = URLDragPreviewProvider(text: "Custom Text Only Preview", favicon: .homeFavicon)
            let preview = snapshot(from: provider)

            assertSnapshot(of: preview, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
        }
    }

}

private class SnapshotWindow: NSWindow {
    override var backingScaleFactor: CGFloat {
        return 1.0
    }
}
