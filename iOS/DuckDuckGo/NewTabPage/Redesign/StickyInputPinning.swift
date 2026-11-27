//
//  StickyInputPinning.swift
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

import CoreGraphics

/// Computes how far a block must move down to stay visible at the top of a scrolling stack.
struct StickyInputPinning {

    /// Top edge of the block, in stack coordinates, without any pinning applied.
    let restingMinY: CGFloat

    /// Height of the block.
    let height: CGFloat

    /// Height of the stack the block lives in.
    let containerHeight: CGFloat

    /// The downward translation that keeps the block's top edge at `pinnedMinY`.
    ///
    /// The block never moves up from its resting position, and never past the bottom of the container.
    func translation(pinnedMinY: CGFloat) -> CGFloat {
        // Staying inside the container's bounds keeps the block receiving touches.
        let maximumTranslation = max(0, containerHeight - (restingMinY + height))
        return min(max(0, pinnedMinY - restingMinY), maximumTranslation)
    }
}
