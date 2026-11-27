//
//  FaviconTestFixtures.swift
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

import AppKit
import FeatureFlags_macOS
import PrivacyConfig
@_spi(Testing) import PixelKit

@testable import DuckDuckGo_Privacy_Browser

/// Favicon data and objects shared by the tests of `FaviconRasterizer` and of the code that uses it.
enum FaviconTestFixtures {

    /// CoreSVG overflows the stack (`EXC_BAD_ACCESS` in `SVGFilter::draw`) when the root `<svg>` and a child
    /// reference the same filter.
    static let recursiveFilterSVG = ##"""
    <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" filter="url(#f)">
      <filter id="f"><feOffset/></filter>
      <rect width="64" height="64" fill="#000" filter="url(#f)"/>
    </svg>
    """##

    static func svg(width: Int, height: Int) -> String {
        ##"<svg xmlns="http://www.w3.org/2000/svg" width="\##(width)" height="\##(height)"><rect width="\##(width)" height="\##(height)" fill="#000"/></svg>"##
    }

    /// A one-page PDF (`%PDF-1.x` header), which CoreImage can't decode but `NSImage(data:)` can.
    static func pdfData() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 32, height: 32)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// A rasterizer with the `faviconWebKitSVGRendering` flag on or off.
    static func makeRasterizer(enabled: Bool = true, pixelFiring: PixelFiring? = nil) -> FaviconRasterizer {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = enabled ? [.faviconWebKitSVGRendering] : []
        return FaviconRasterizer(featureFlagger: featureFlagger, pixelFiring: pixelFiring)
    }
}
