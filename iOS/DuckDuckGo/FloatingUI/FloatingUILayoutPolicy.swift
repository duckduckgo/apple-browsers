//
//  FloatingUILayoutPolicy.swift
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

import Core
import UIKit

struct FloatingWebViewEdgeBleedGeometry: Equatable {
    let topFrame: CGRect?
    let bottomFrame: CGRect?
    let topSnapshotRect: CGRect?
    let bottomSnapshotRect: CGRect?
}

enum FloatingUILayoutPolicy {

    static func shouldApplyFloatingTopContentInset(isFloatingUIEnabled: Bool,
                                                   addressBarPosition: AddressBarPosition,
                                                   isUnifiedToggleInputAffectingLayout: Bool) -> Bool {
        isFloatingUIEnabled && addressBarPosition == .top && !isUnifiedToggleInputAffectingLayout
    }

    static func webViewPortraitInsets(topBarBottom: CGFloat,
                                      safeAreaTop: CGFloat,
                                      bottomBarTop: CGFloat,
                                      containerHeight: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(top: max(topBarBottom, safeAreaTop),
                     left: 0,
                     bottom: max(0, containerHeight - bottomBarTop),
                     right: 0)
    }

    static func webViewFrame(in bounds: CGRect,
                             portraitInsets: UIEdgeInsets,
                             usesFullHeight: Bool) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return bounds }
        guard !usesFullHeight else { return bounds }

        let minY = min(max(bounds.minY + portraitInsets.top, bounds.minY), bounds.maxY)
        let maxY = max(min(bounds.maxY - portraitInsets.bottom, bounds.maxY), minY)
        return CGRect(x: bounds.minX, y: minY, width: bounds.width, height: maxY - minY)
    }

    static func edgeBleedGeometry(containerBounds: CGRect,
                                  webViewFrame: CGRect,
                                  webViewBounds: CGRect,
                                  hasTopFixedElement: Bool,
                                  hasBottomFixedElement: Bool,
                                  snapshotStripHeight: CGFloat = 2,
                                  snapshotEdgeInset: CGFloat = 8) -> FloatingWebViewEdgeBleedGeometry {
        let stripHeight = min(max(0, snapshotStripHeight), webViewBounds.height)
        let edgeInset = min(max(0, snapshotEdgeInset), max(0, webViewBounds.height - stripHeight))
        let topHeight = max(0, webViewFrame.minY - containerBounds.minY)
        let bottomHeight = max(0, containerBounds.maxY - webViewFrame.maxY)

        let topFrame = hasTopFixedElement && topHeight > 0
            ? CGRect(x: webViewFrame.minX, y: containerBounds.minY, width: webViewFrame.width, height: topHeight)
            : nil
        let bottomFrame = hasBottomFixedElement && bottomHeight > 0
            ? CGRect(x: webViewFrame.minX, y: webViewFrame.maxY, width: webViewFrame.width, height: bottomHeight)
            : nil
        let topSnapshotRect = topFrame != nil && stripHeight > 0
            ? CGRect(x: webViewBounds.minX, y: webViewBounds.minY + edgeInset, width: webViewBounds.width, height: stripHeight)
            : nil
        let bottomSnapshotRect = bottomFrame != nil && stripHeight > 0
            ? CGRect(x: webViewBounds.minX, y: webViewBounds.maxY - stripHeight - edgeInset, width: webViewBounds.width, height: stripHeight)
            : nil

        return FloatingWebViewEdgeBleedGeometry(
            topFrame: topFrame,
            bottomFrame: bottomFrame,
            topSnapshotRect: topSnapshotRect,
            bottomSnapshotRect: bottomSnapshotRect)
    }

    static func shouldHostOmnibarInFloatingToolbar(isFloatingUIEnabled: Bool,
                                                   addressBarPosition: AddressBarPosition,
                                                   isUnifiedToggleInputVisible: Bool,
                                                   isMinimalChromeLayout: Bool) -> Bool {
        // Excludes minimal chrome, where the toolbar is hidden and would take the omnibar with it.
        isFloatingUIEnabled && addressBarPosition.isBottom && !isUnifiedToggleInputVisible && !isMinimalChromeLayout
    }

    static func shouldShowFloatingDomainCapsule(isFloatingUIEnabled: Bool,
                                                isUnifiedToggleInputActive: Bool,
                                                isAITab: Bool,
                                                isMinimalChromeLayout: Bool) -> Bool {
        isFloatingUIEnabled && !isUnifiedToggleInputActive && !isAITab && !isMinimalChromeLayout
    }
}
