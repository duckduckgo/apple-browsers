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

// We only support chat for now.  More options will be added in a future customisation project.
enum OmniBarAccessoryType {
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

    func beginEditing(animated: Bool)
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
    
    /// Sets the dynamic Dax Easter Egg logo URL for display in the omnibar privacy icon.
    /// When a URL is provided, the privacy icon will load and display the dynamic logo image.
    /// When nil is provided, the privacy icon resets to the default static Dax logo.
    ///
    /// - Parameter logoURL: Absolute URL string of the dynamic logo to display, or nil to reset to default
    func setDaxEasterEggLogoURL(_ logoURL: String?)

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
