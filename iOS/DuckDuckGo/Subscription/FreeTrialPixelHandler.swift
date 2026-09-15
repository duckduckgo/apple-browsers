//
//  FreeTrialPixelHandler.swift
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
import Subscription
import Core
import PixelKit

public struct FreeTrialPixelHandler: FreeTrialPixelHandling {

    public init() {}

    public func fireFreeTrialStart() {
        PixelKit.fire(Pixel.Event.privacyProFreeTrialStart)
    }

    public func fireFreeTrialVPNActivation(activationDay: FreeTrialActivationDay) {
        PixelKit.fire(Pixel.Event.privacyProFreeTrialVPNActivation,
                      options: .parameters(["activation_day": activationDay.rawValue]))
    }

    public func fireFreeTrialPIRActivation(activationDay: FreeTrialActivationDay) {
        PixelKit.fire(Pixel.Event.privacyProFreeTrialPIRActivation,
                      options: .parameters(["activation_day": activationDay.rawValue]))
    }

    public func fireFreeTrialDuckAIActivation(activationDay: FreeTrialActivationDay) {
        PixelKit.fire(Pixel.Event.privacyProFreeTrialDuckAIActivation,
                      options: .parameters(["activation_day": activationDay.rawValue]))
    }
}
