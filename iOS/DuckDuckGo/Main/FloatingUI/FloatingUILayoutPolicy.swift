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

enum FloatingUILayoutPolicy {

    struct WebViewLayout: Equatable {
        let topAnchorConstant: CGFloat
        let bottomAnchorConstant: CGFloat
        let obscuredContentInsets: UIEdgeInsets
    }

    static func webViewLayout(obscuredContentInsets: UIEdgeInsets) -> WebViewLayout {
        return WebViewLayout(topAnchorConstant: 0,
                             bottomAnchorConstant: 0,
                             obscuredContentInsets: obscuredContentInsets)
    }

    static func shouldApplyFloatingTopContentInset(isFloatingUIEnabled: Bool,
                                                   addressBarPosition: AddressBarPosition,
                                                   isUnifiedToggleInputAffectingLayout: Bool) -> Bool {
        isFloatingUIEnabled && addressBarPosition == .top && !isUnifiedToggleInputAffectingLayout
    }

    static func newTabPageBottomAdditionalSafeAreaInset(isFloatingUIEnabled: Bool,
                                                        addressBarPosition: AddressBarPosition,
                                                        floatingBottomObscuredHeight: CGFloat,
                                                        safeAreaBottom: CGFloat,
                                                        omnibarHeight: CGFloat,
                                                        reservesAddressBarSpace: Bool = true) -> CGFloat {
        if isFloatingUIEnabled {
            return max(0, floatingBottomObscuredHeight - safeAreaBottom)
        }
        return addressBarPosition.isBottom && reservesAddressBarSpace ? omnibarHeight : 0
    }

    /// Fraction of a bar's slide travel that is still on screen while the domain capsule morph owns the
    /// transition. The pill morphs out of the bar's *resting* frame, so the bar has to hold that frame
    /// until the cross-fade has finished — sliding during the fade separates the two and the bar
    /// visibly creeps away before it disappears. It slides out over `[0, handoffStart]` instead, by
    /// which point it is no longer drawn.
    static func chromeOnScreenFraction(barsVisibilityPercent: CGFloat, handoffStart: CGFloat) -> CGFloat {
        guard handoffStart > 0 else { return barsVisibilityPercent > 0 ? 1 : 0 }
        let clampedPercent = max(0, min(1, barsVisibilityPercent))
        return min(1, clampedPercent / handoffStart)
    }

    /// Linear ramp of `percent` from 0 at `start` to 1 at `end`, clamped outside that range. Shared by
    /// both halves of the top bar's bar<->pill crossfade so they always sum to 1.
    static func rampedProgress(_ percent: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return percent < end ? 0 : 1 }
        return ((percent - start) / (end - start)).clamped(to: 0...1)
    }

    /// One frame of the bottom bar's collapse into the domain pill.
    struct BottomMorphPose: Equatable {
        /// The glass shape. Drawn by the bar at rest and by the pill from the first step on.
        let frame: CGRect
        let cornerRadius: CGFloat
        /// Opacity of the bar's own content (address field and buttons), which rides inside the shape.
        let barContentAlpha: CGFloat
        /// True once the pill draws the glass in place of the bar. Exactly one of them does, so the
        /// glass is never dimmed by a cross-fade.
        let isGlassOnPill: Bool
        let domainLabelAlpha: CGFloat
        /// 1 at rest, 0 once collapsed: the bar floats on a shadow, the pill does not.
        let shadowAmount: CGFloat
        /// Maps the bar's resting panel onto `frame`.
        let barTransform: CGAffineTransform
    }

    /// The pill takes the glass over just below rest, where its frame is within a point of the bar's.
    /// Not exactly 1, so a spring settling around rest doesn't flip the glass back and forth.
    static let bottomMorphGlassHandoff: CGFloat = 0.995

    /// The bar's content has fully faded at and below this visibility.
    static let bottomMorphContentFadeEnd: CGFloat = 0.6

    /// The pill's domain text fades in across this band, overlapping the end of the bar's URL fade.
    static let bottomMorphDomainLabelFade: ClosedRange<CGFloat> = 0.5...0.75

    /// How far past the resting bar the shape may travel while the spring settles. The collapsed end
    /// gets none: a pill narrower than its label truncates the domain for a few frames.
    static let bottomMorphOvershoot: CGFloat = 0.04

    /// Size, position and corner radius all follow `barsVisibilityPercent` across the whole range, so
    /// the collapse has no stage where the shape stands still. The bar's content is scaled onto the
    /// same frame, so it can't be seen at a different size from the glass around it.
    static func bottomMorphPose(barsVisibilityPercent: CGFloat,
                                expandedFrame: CGRect,
                                restFrame: CGRect,
                                expandedCornerRadius: CGFloat) -> BottomMorphPose {
        let shapePercent = barsVisibilityPercent.clamped(to: 0...(1 + bottomMorphOvershoot))
        let collapse = 1 - shapePercent
        func mix(_ expanded: CGFloat, _ rest: CGFloat) -> CGFloat { expanded + (rest - expanded) * collapse }

        let width = max(0, mix(expandedFrame.width, restFrame.width))
        let height = max(0, mix(expandedFrame.height, restFrame.height))
        let frame = CGRect(x: mix(expandedFrame.midX, restFrame.midX) - width / 2,
                           y: mix(expandedFrame.midY, restFrame.midY) - height / 2,
                           width: width,
                           height: height)
        let cornerRadius = min(height / 2, max(0, mix(expandedCornerRadius, restFrame.height / 2)))

        var barTransform = CGAffineTransform.identity
        if expandedFrame.width > 0, expandedFrame.height > 0 {
            barTransform = CGAffineTransform(scaleX: width / expandedFrame.width, y: height / expandedFrame.height)
                .concatenating(CGAffineTransform(translationX: frame.midX - expandedFrame.midX,
                                                 y: frame.midY - expandedFrame.midY))
        }
        return BottomMorphPose(
            frame: frame,
            cornerRadius: cornerRadius,
            barContentAlpha: rampedProgress(barsVisibilityPercent, from: bottomMorphContentFadeEnd, to: 1),
            isGlassOnPill: barsVisibilityPercent < bottomMorphGlassHandoff,
            domainLabelAlpha: 1 - rampedProgress(barsVisibilityPercent,
                                                 from: bottomMorphDomainLabelFade.lowerBound,
                                                 to: bottomMorphDomainLabelFade.upperBound),
            shadowAmount: barsVisibilityPercent.clamped(to: 0...1),
            barTransform: barTransform)
    }

    /// Height obscured by the visible bottom chrome, measured from the web view container's bottom edge
    /// (the screen bottom). The floating web view is resized up by this amount so a page `position: fixed`
    /// footer pins to the top of whatever is on screen at the bottom:
    /// - toolbar shown -> `toolbarSlotHeight` (footer above the toolbar),
    /// - toolbar still on screen during the morph -> `visibleToolbarHeight` (footer above the live bar),
    /// - toolbar hidden + bottom capsule -> `bottomCapsuleObscuredHeight` (footer above the capsule),
    /// - neither -> `safeAreaBottom` (footer at the safe area).
    ///
    /// `max` gives a smooth crossover: the shrinking toolbar term and the on-screen floor dominate while
    /// the bars are visible, then the (stable) capsule / safe-area term takes over once the bars have hidden.
    static func webViewBottomObscuredHeight(barsVisibilityPercent: CGFloat,
                                            toolbarSlotHeight: CGFloat,
                                            visibleToolbarHeight: CGFloat = 0,
                                            bottomCapsuleObscuredHeight: CGFloat,
                                            safeAreaBottom: CGFloat) -> CGFloat {
        let clampedPercent = max(0, min(1, barsVisibilityPercent))
        return max(toolbarSlotHeight * clampedPercent, visibleToolbarHeight, bottomCapsuleObscuredHeight, safeAreaBottom)
    }

    /// Top counterpart of `webViewBottomObscuredHeight`. `visibleChromeHeight` is the on-screen floor
    /// while the top bar is pinned through the capsule hand-off, so a page `position: fixed` header
    /// stays below the bar the user can still see instead of sliding under it.
    static func webViewTopObscuredHeight(barsVisibilityPercent: CGFloat,
                                         expandedChromeHeight: CGFloat,
                                         visibleChromeHeight: CGFloat = 0,
                                         topCapsuleObscuredHeight: CGFloat,
                                         safeAreaTop: CGFloat) -> CGFloat {
        let clampedPercent = max(0, min(1, barsVisibilityPercent))
        return max(expandedChromeHeight * clampedPercent, visibleChromeHeight, topCapsuleObscuredHeight, safeAreaTop)
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
