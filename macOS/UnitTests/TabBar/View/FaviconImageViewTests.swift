//
//  FaviconImageViewTests.swift
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

final class FaviconImageViewTests: XCTestCase {

    private var snapshotWindowSD: SnapshotWindow!

    override func setUp() {
        super.setUp()
        snapshotWindowSD = SnapshotWindow(contentRect: Constants.imageBounds, scale: Constants.scaleSD)
    }

    override func tearDown() {
        super.tearDown()
        snapshotWindowSD = nil
    }

    /// `FaviconImageView` was built to work around a macOS 26 Rendering Issue:
    ///
    ///     -   Traced back to `NSImage(dataUsingCIImage:)` + `NSImageView`
    ///     -   Only affects SD displays
    ///
    /// Reference: https://app.asana.com/1/137249556945/project/1201048563534612/task/1211961221757398/comment/1212149100646594?focus=true
    ///
    func testFaviconRendersCorrectlyOnDisplaysWithLowResolution() {
        guard let data = NSImage.homeFavicon.pngData(), let image = NSImage(dataUsingCIImage: data) else {
            XCTFail("Unable to load Test Image")
            return
        }

        let faviconView = FaviconImageView(image: image)
        faviconView.forceCustomDrawing = true
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        faviconView.bounds = Constants.imageBounds
        snapshotWindowSD.contentView = faviconView

        assertSnapshot(of: faviconView, as: .image(perceptualPrecision: 1.0), named: "sd")
    }
}

private enum Constants {
    static let scaleSD = CGFloat(1)
    static let imageBounds = NSRect(x: 0, y: 0, width: 16, height: 16)
}

private class SnapshotWindow: NSWindow {
    private var scale: CGFloat = 1

    convenience init(contentRect: NSRect, styleMask style: NSWindow.StyleMask = [], backing backingStoreType: NSWindow.BackingStoreType = .buffered, defer flag: Bool = false, scale: CGFloat) {
        self.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.scale = scale
    }

    override var backingScaleFactor: CGFloat {
        scale
    }
}
