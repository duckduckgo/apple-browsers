//
//  OmniBarEditingStateTransitioning.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

protocol OmniBarEditingStateTransitioning: AnyObject {
    var switchBarVC: SwitchBarViewController { get }
    var actionBarView: UIView? { get }
    func setLogoYOffset(_ offset: CGFloat)

    // Escape Hatch
    func setLogoHidden(_ hidden: Bool)
    /// When true, use opaque-from-frame-0 transition and single-logo behaviour. Gated by showNTPAfterIdleReturn.
    var useNewTransitionBehaviour: Bool { get }
    /// When true, the NTP is showing the escape hatch card; the transition hides the editing-state Dax logo so only the NTP logo is visible.
    var isEscapeHatchCardVisible: Bool { get }
}
