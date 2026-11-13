//
//  NewTabTransitionConfiguration.swift
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

/// The tunable values of the new-tab transition, editable from the debug screen.
struct NewTabTransitionConfiguration: Codable, Equatable {

    typealias Tuning = NewTabTransitionTuning

    var isEnabled = true
    var inTabOrigin = Tuning.inTabOrigin
    var tabManagerOrigin = Tuning.tabManagerOrigin
    var rightOfCenter = Tuning.rightOfCenter
    var belowCenter = Tuning.belowCenter
    var cornerRadius = Tuning.cornerRadius
    var roundsCorners = Tuning.roundsCorners
    var fadesInNewPage = Tuning.fadesInNewPage
    var usesSpring = Tuning.usesSpring
    var tabManagerStaysStill = Tuning.tabManagerStaysStill
    var oldKeyboard = Tuning.oldKeyboard
    var isSlowMotion = false

    func origin(for entryPoint: Tuning.EntryPoint) -> Tuning.Origin {
        switch entryPoint {
        case .inTab: return inTabOrigin
        case .tabManager: return tabManagerOrigin
        }
    }

    func motion(for origin: Tuning.Origin) -> Tuning.Motion {
        switch origin {
        case .rightOfCenter: return rightOfCenter
        case .belowCenter: return belowCenter
        }
    }

    func duration(of motion: Tuning.Motion) -> TimeInterval {
        motion.duration * (isSlowMotion ? Tuning.slowMotionFactor : 1)
    }
}
