//
//  WebViewTransitionGeometry.swift
//  DuckDuckGo
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

import UIKit

/// Pure frame math for the tab-switcher ↔ web-view transition, separated from
/// `WebViewTransition` so the NaN/Inf guarding can be unit-tested standalone.
enum WebViewTransitionGeometry {

    /// Height-to-width ratio of the preview, or nil for a degenerate (zero /
    /// non-finite) size — keeps NaN/Inf out of the frames handed to CALayer.
    static func aspectRatio(of previewSize: CGSize) -> CGFloat? {
        guard previewSize.width > 0, previewSize.height > 0,
              previewSize.width.isFinite, previewSize.height.isFinite else { return nil }
        return previewSize.height / previewSize.width
    }

    static func previewFrame(for cellBounds: CGSize, previewSize: CGSize, isGridViewEnabled: Bool) -> CGRect {
        guard isGridViewEnabled, let previewAspectRatio = aspectRatio(of: previewSize) else {
            return CGRect(origin: .zero, size: cellBounds)
        }

        let horizontalInset = TabViewGridCell.Constants.previewHorizontalInset / 2
        let availableWidth = cellBounds.width - TabViewGridCell.Constants.previewHorizontalInset
        let availableHeight = cellBounds.height
            - TabViewGridCell.Constants.headerHeight
            - TabViewGridCell.Constants.previewBottomPadding
        guard availableWidth > 0, availableHeight > 0 else {
            return CGRect(origin: .zero, size: cellBounds)
        }
        let containerAspectRatio = availableHeight / availableWidth

        if previewAspectRatio <= containerAspectRatio {
            let width = availableHeight / previewAspectRatio
            return CGRect(x: (cellBounds.width - width) / 2,
                          y: TabViewGridCell.Constants.headerHeight,
                          width: width,
                          height: availableHeight)
        }

        return CGRect(x: horizontalInset,
                      y: TabViewGridCell.Constants.headerHeight,
                      width: availableWidth,
                      height: availableWidth * previewAspectRatio)
    }

    static func destinationImageFrame(for containerSize: CGSize, previewSize: CGSize?) -> CGRect {
        guard let previewSize, let previewAspectRatio = aspectRatio(of: previewSize) else {
            return CGRect(origin: .zero, size: containerSize)
        }

        return CGRect(x: 0,
                      y: 0,
                      width: containerSize.width,
                      height: containerSize.width * previewAspectRatio)
    }
}
