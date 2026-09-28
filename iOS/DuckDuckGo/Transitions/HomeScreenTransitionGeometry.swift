//
//  HomeScreenTransitionGeometry.swift
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

enum HomeScreenTransitionGeometry {

    /// Aspect-fit frame for a captured new-tab-page snapshot inside a shrinking/growing
    /// tab-cell container. Fitting on the smaller ratio scales the page uniformly instead
    /// of stretching a `resizableSnapshotView` to the container's (often much wider) bounds.
    static func snapshotFrame(for sourceSize: CGSize,
                              in containerBounds: CGRect,
                              isGridViewEnabled: Bool) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0,
              sourceSize.width.isFinite, sourceSize.height.isFinite else {
            return containerBounds
        }

        if !isGridViewEnabled {
            let scale = containerBounds.width / sourceSize.width
            return CGRect(x: containerBounds.minX,
                          y: containerBounds.minY,
                          width: containerBounds.width,
                          height: sourceSize.height * scale)
        }

        let scale = min(containerBounds.width / sourceSize.width,
                        containerBounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(x: containerBounds.midX - size.width / 2,
                      y: containerBounds.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }
}
