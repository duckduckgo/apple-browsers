//
//  SwipeToNewTabPull.swift
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

import Foundation

/// Tunables for opening a new tab by pulling past the last tab. Distances are on-screen, after edge resistance.
enum SwipeToNewTabTuning {
    static let commitDistance: CGFloat = 120
    /// How far back under `commitDistance` a committed pull must go to let go, so it doesn't flicker at the line.
    static let releaseHysteresis: CGFloat = 14
    /// A pull moving faster than this past the line is a swipe through tabs, not a request for a new one.
    static let maximumCommitSpeed: CGFloat = 220
    /// How quickly the measured pull speed follows the finger; lower is smoother.
    static let speedSmoothing: CGFloat = 0.35
    /// `.hold` asks for a shorter pull, since resting there is what makes it deliberate.
    static let holdCommitDistance: CGFloat = 90
    /// How long `.hold` needs the pull to rest past its line.
    static let holdDuration: TimeInterval = 0.3
    /// A `.hold` pull slower than this counts as resting; moving faster starts the hold over.
    static let holdRestingSpeed: CGFloat = 40
    /// The fastest the ring fills, in pulls per second, so a quick swipe fills it gradually rather than at once.
    static let ringFillRate: CGFloat = 2.5
    static let affordanceDiameter: CGFloat = 52
    static let affordanceMinimumScale: CGFloat = 0.45
    static let committedScale: CGFloat = 1.1
    /// Share of `commitDistance` over which the affordance fades in.
    static let fadeInProgress: CGFloat = 0.15
    /// How long the released page takes to slide off the new tab opening beneath it.
    static let openDuration: TimeInterval = 0.22
    /// The "+" swells to this as it fades out over the opening tab.
    static let openedScale: CGFloat = 1.3
}

/// Prototype styles for the pull, picked from the address bar's long-press menu.
enum SwipeToNewTabStyle: String, CaseIterable {
    /// A "+" grows in the gap; reaching the line slowly commits.
    case grow
    /// Like `grow`, but the pull has to rest past the line for `holdDuration`.
    case hold
    /// The "+" rides the page's trailing edge, half behind it, and detaches as the pull grows.
    case edge

    private static let storageKey = "com.duckduckgo.ios.swipeToNewTab.prototypeStyle"

    static var current: SwipeToNewTabStyle {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .hold }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    var title: String {
        switch self {
        case .grow: return "Grow"
        case .hold: return "Hold to confirm"
        case .edge: return "Ride the page edge"
        }
    }
}

/// A pull past the last tab: commits once it rests far enough out, and lets go if pulled back.
struct SwipeToNewTabPull {

    private typealias Tuning = SwipeToNewTabTuning

    enum Change: Equatable {
        case none
        case committed
        case released
    }

    let requiresHold: Bool
    let commitDistance: CGFloat
    private(set) var distance: CGFloat = 0
    private(set) var speed: CGFloat = 0
    private(set) var isCommitted = false
    private(set) var holdProgress: CGFloat = 0
    /// What the ring shows: follows `progress`, but fills no faster than `ringFillRate`. Commits wait for it to fill.
    private(set) var ringProgress: CGFloat = 0
    private var lastSampleTime: TimeInterval?

    init(requiresHold: Bool = false) {
        self.requiresHold = requiresHold
        commitDistance = requiresHold ? Tuning.holdCommitDistance : Tuning.commitDistance
    }

    var progress: CGFloat {
        min(distance / commitDistance, 1)
    }

    /// Only a finger still on screen can commit or let go; a settling bounce just shrinks the pull.
    mutating func update(distance newDistance: CGFloat, isDragging: Bool, at time: TimeInterval) -> Change {
        let newDistance = max(newDistance, 0)
        let elapsed = lastSampleTime.map { max(time - $0, 0) } ?? 0
        measureSpeed(to: newDistance, at: time)
        distance = newDistance
        fillRing(over: elapsed)
        guard isDragging else {
            holdProgress = 0
            return .none
        }
        if isCommitted {
            guard distance < commitDistance - Tuning.releaseHysteresis else { return .none }
            isCommitted = false
            return .released
        }
        guard distance >= commitDistance, ringProgress >= 1 else {
            holdProgress = 0
            return .none
        }
        return requiresHold ? fillHold(over: elapsed) : commitIfSlow()
    }

    private mutating func fillRing(over elapsed: TimeInterval) {
        ringProgress = min(progress, ringProgress + Tuning.ringFillRate * CGFloat(elapsed))
    }

    private mutating func commitIfSlow() -> Change {
        guard speed <= Tuning.maximumCommitSpeed else { return .none }
        isCommitted = true
        return .committed
    }

    /// Counts how long the pull has rested past the line; moving starts the count over.
    private mutating func fillHold(over elapsed: TimeInterval) -> Change {
        guard speed <= Tuning.holdRestingSpeed else {
            holdProgress = 0
            return .none
        }
        holdProgress = min(holdProgress + CGFloat(elapsed / Tuning.holdDuration), 1)
        guard holdProgress >= 1 else { return .none }
        isCommitted = true
        return .committed
    }

    private mutating func measureSpeed(to newDistance: CGFloat, at time: TimeInterval) {
        defer { lastSampleTime = time }
        guard let lastSampleTime, time > lastSampleTime else { return }
        let instantSpeed = abs(newDistance - distance) / CGFloat(time - lastSampleTime)
        speed += (instantSpeed - speed) * Tuning.speedSmoothing
    }
}
