//
//  RedesignedNewTabPageLayout.swift
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

/// Geometry for the redesigned page only. All rectangles use the owning view's local coordinates.
enum RedesignedNewTabPageLayout {
    static let maximumContentWidth: CGFloat = 720

    static func contentFrame(in available: CGRect, avoiding regions: [CGRect], prefersTrailing: Bool) -> CGRect {
        var result = available
        for region in regions {
            let intersection = result.intersection(region)
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            // Keep the existing single scroll view in a usable pane rather than recreating its content.
            let candidates = [
                CGRect(x: result.minX, y: result.minY, width: intersection.minX - result.minX, height: result.height),
                CGRect(x: intersection.maxX, y: result.minY, width: result.maxX - intersection.maxX, height: result.height),
                CGRect(x: result.minX, y: result.minY, width: result.width, height: intersection.minY - result.minY),
                CGRect(x: result.minX, y: intersection.maxY, width: result.width, height: result.maxY - intersection.maxY)
            ].filter { !$0.isEmpty }
            result = candidates.max { first, second in
                let firstArea = first.width * first.height
                let secondArea = second.width * second.height
                if firstArea != secondArea { return firstArea < secondArea }
                return prefersTrailing ? first.minX < second.minX : first.minX > second.minX
            } ?? .zero
        }
        let width = min(result.width, maximumContentWidth)
        return CGRect(x: result.midX - width / 2, y: result.minY, width: width, height: result.height)
    }

    static func activeReservedFrames(in view: UIView) -> [CGRect] {
        // Xcode 26 remains supported; the Duo API is only present in the verified Xcode 27.1 SDK.
        #if compiler(>=6.4) && !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) {
            let regions = view.reservedRegions(kind: .division, options: .includeInactive)
                + view.reservedRegions(kind: .occlusion, options: .includeInactive)
            // Frames already include the system's protective margins.
            return regions.filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }

    static func favoriteColumnCount(width: CGFloat, minimumTileWidth: CGFloat) -> Int {
        guard width > 0 else { return 5 }
        return max(1, min(8, Int((width + 8) / (minimumTileWidth + 8))))
    }
}
