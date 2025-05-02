//
//  OmniBar.swift
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

import Foundation
import PrivacyDashboard

enum OmniBarAccessoryType {
     case share
     case chat
 }

protocol OmniBar: AnyObject {
    var barView: any OmniBarView { get }

    var isBackButtonEnabled: Bool { get set }
    var isForwardButtonEnabled: Bool { get set }

    var omniDelegate: OmniBarDelegate? { get set }

    var isTextFieldEditing: Bool { get }
    var text: String? { get set }

    // Updates text and calls a query update function
    func updateQuery(_ query: String?)
    func refreshText(forUrl url: URL?, forceFullURL: Bool)

    func beginEditing()
    func endEditing()

    func showSeparator()
    func hideSeparator()
    func moveSeparatorToTop()
    func moveSeparatorToBottom()

    func useSmallTopSpacing()
    func useRegularTopSpacing()

    func enterPhoneState()
    func enterPadState()

    func startBrowsing()
    func stopBrowsing()
    func startLoading()
    func stopLoading()
    func cancel()

    func removeTextSelection()
    func selectTextToEnd(_ offset: Int)

    func updateAccessoryType(_ type: OmniBarAccessoryType)

    func showOrScheduleCookiesManagedNotification(isCosmetic: Bool)

    func showOrScheduleOnboardingPrivacyIconAnimation()
    func dismissOnboardingPrivacyIconAnimation()

    func startTrackersAnimation(_ privacyInfo: PrivacyInfo, forDaxDialog: Bool)
    func updatePrivacyIcon(for privacyInfo: PrivacyInfo?)
    func hidePrivacyIcon()
    func resetPrivacyIcon(for url: URL?)

    func cancelAllAnimations()
    func completeAnimationForDaxDialog()
}

extension OmniBar {
    func adjust(for position: AddressBarPosition) {
        switch position {
        case .bottom:
            moveSeparatorToTop()
            useSmallTopSpacing()
        case .top:
            moveSeparatorToBottom()
            useRegularTopSpacing()
        }
    }
}
