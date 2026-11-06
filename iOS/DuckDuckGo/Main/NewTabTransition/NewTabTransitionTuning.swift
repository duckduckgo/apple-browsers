//
//  NewTabTransitionTuning.swift
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

/// Every value of the new-tab container transform. Defaults come from design's web prototype.
enum NewTabTransitionTuning {

    enum Origin: String, Codable, CaseIterable {
        case rightOfCenter
        case belowCenter
        /// Grows from where the user tapped, with the right-of-center motion values.
        case tapLocation
    }

    /// What happens to a keyboard left up on the old screen.
    enum OldKeyboard: String, Codable, CaseIterable {
        case leavesInstantly
        case slidesDown
        /// Stays up over the card, so a new tab that raises its own keyboard never drops it.
        case staysUp

        /// A new page without its own keyboard has nothing to keep the old one up for.
        func forNewPage(raisingKeyboard: Bool) -> Self {
            self == .staysUp && !raisingKeyboard ? .leavesInstantly : self
        }
    }

    enum EntryPoint {
        case inTab
        case tabManager
    }

    struct Motion: Codable, Equatable {
        /// New page size at the first frame, as a fraction of the screen.
        var startScale: CGFloat
        /// Distance of the new page's center from the screen center: fraction of width (right) or height (below).
        var offset: CGFloat
        var oldPageScale: CGFloat
        /// How far the old page moves left, as a fraction of the screen width.
        var oldPageDrift: CGFloat
        var dimming: CGFloat
        var duration: TimeInterval
    }

    static let rightOfCenter = Motion(startScale: 0.8, offset: 0.25, oldPageScale: 0.95, oldPageDrift: 0.08, dimming: 0.25, duration: 0.5)
    static let belowCenter = Motion(startScale: 0.8, offset: 0.15, oldPageScale: 0.95, oldPageDrift: 0, dimming: 0.25, duration: 0.5)

    static let inTabOrigin = Origin.rightOfCenter
    static let tabManagerOrigin = Origin.belowCenter

    /// Close to the iPhone display corner radius, so the card lands on the screen edge.
    static let cornerRadius: CGFloat = 55
    static let roundsCorners = true
    static let fadesInNewPage = true
    static let usesSpring = true
    static let tabManagerStaysStill = false
    /// Stays up, so a new tab that raises its own keyboard never drops and re-raises it.
    static let oldKeyboard = OldKeyboard.staysUp

    static let curveControlPoint1 = CGPoint(x: 0.2, y: 0)
    static let curveControlPoint2 = CGPoint(x: 0, y: 1)
    /// Dimming the old page reaches while the new tab is still being built, so the tap shows at once.
    static let tapFeedbackDimming: CGFloat = 0.12
    /// How dark UIKit's dimmed sheet backdrop makes the screen, measured from recordings.
    static let sheetBackdropDimming: CGFloat = 0.2
    /// Share of the duration, in time, over which the new page fades in.
    static let fadeInPortion = 0.3
    /// Share of the duration over which the old page reaches full dimming.
    static let dimmingPortion = 0.35
    /// How far into the grow the new tab's keyboard starts, so the two land together.
    static let keyboardStartPortion = 0.2

    static let shadowOpacity: Float = 0.55
    static let shadowRadius: CGFloat = 35
    static let shadowOffset = CGSize(width: 0, height: 24)
    static let shadowPeakAlpha: CGFloat = 0.7

    /// Replaces the grow when Reduce Motion is on.
    static let reduceMotionCrossfadeDuration: TimeInterval = 0.25

    static let slowMotionFactor = 4.0
}
