//
//  UnifiedToggleInputDisplayState.swift
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

/// The single source of truth for what the UTI is showing. Owned by `UTIStateMachine`; drives the
/// render computation and every `displayState`-derived boolean.
enum UnifiedToggleInputDisplayState: Equatable {
    case hidden
    case contextualChat
    case aiTab(AITabState)
    case omnibar(OmnibarState)

    enum AITabState: Equatable, CaseIterable {
        case collapsed
        case expanded
    }

    enum OmnibarState: Equatable, CaseIterable {
        case active
        case inactive
    }
}

/// A display-state transition the coordinator emits for `MainViewController` to realise. Each intent
/// carries the *previous* state so the handler can pick the right animation from the (from, to) pair.
enum UnifiedToggleInputIntent: Equatable {
    case showCollapsed(from: UnifiedToggleInputDisplayState)
    case showExpanded(from: UnifiedToggleInputDisplayState)
    case showOmnibarEditing(expandedHeight: CGFloat, pendingExpandedHeight: CGFloat? = nil)
    case showOmnibarInactive
    case showOmnibarActive
    case hideOmnibarEditing(animated: Bool)
    case hide
}

/// First-class wrapper around "should this UI mutation animate, or snap?" Both branches
/// take a closure of work to run — the wrapper handles the animation-context plumbing
/// (`UIView.animate` vs `UIView.performWithoutAnimation`) so call sites stay flat.
enum UTIAnimationStyle {
    case snap
    case animated(duration: TimeInterval, options: UIView.AnimationOptions, layoutTarget: UIView)

    func perform(_ body: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .snap:
            UIView.performWithoutAnimation(body)
            completion?(true)
        case let .animated(duration, options, layoutTarget):
            UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
                body()
                layoutTarget.layoutIfNeeded()
            }, completion: completion)
        }
    }

    /// Duration of this style — `0` for snap, the configured duration for animated. Useful
    /// for matching parallel animations (e.g. `adjustUI(withKeyboardFrame:in:)`) to the same
    /// timing.
    var duration: TimeInterval {
        switch self {
        case .snap: return 0
        case let .animated(duration, _, _): return duration
        }
    }
}

extension UnifiedToggleInputIntent {
    enum AnimationConstants {
        /// In-place pose morph on Duck.ai (collapsed ↔ expanded card).
        static let aiTabPoseMorphDuration: TimeInterval = 0.35
    }

    /// Animation style derived from the intent's transition. The (from, to) pair is the only
    /// signal needed — adding new transitions means adding new cases in the matrix below, not
    /// scattering `if/else` across handlers.
    func animationStyle(layoutTarget: UIView) -> UTIAnimationStyle {
        switch self {
        case let .showCollapsed(from):
            return Self.transitionStyle(from: from, to: .aiTab(.collapsed), layoutTarget: layoutTarget)
        case let .showExpanded(from):
            return Self.transitionStyle(from: from, to: .aiTab(.expanded), layoutTarget: layoutTarget)
        case .hide, .showOmnibarEditing, .showOmnibarInactive, .showOmnibarActive, .hideOmnibarEditing:
            // `.hide` is always a snap (no animatable transition pair); the omnibar intents
            // own bespoke animation flows and pick their own style.
            return .snap
        }
    }

    private static func transitionStyle(from: UnifiedToggleInputDisplayState,
                                        to: UnifiedToggleInputDisplayState,
                                        layoutTarget: UIView) -> UTIAnimationStyle {
        switch (from, to) {
        case (.aiTab(.expanded), .aiTab(.collapsed)),
             (.aiTab(.collapsed), .aiTab(.expanded)):
            return .animated(duration: AnimationConstants.aiTabPoseMorphDuration,
                             options: .curveEaseInOut,
                             layoutTarget: layoutTarget)
        default:
            // Fresh entry into a state from a different layout (tab swipe, app launch,
            // omnibar dismiss, hide). The outer constraint changes shouldn't be animated;
            // the destination should just BE there.
            return .snap
        }
    }
}
