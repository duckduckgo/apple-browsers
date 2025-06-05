//
//  DefaultBrowserAndDockPromptPixelEvent.swift
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
import PixelKit

/// An enum defining the pixel events for SAD/ATT prompts.
/// > Related links:
/// [Pixel Definition](https://app.asana.com/1/137249556945/project/1206329551987282/task/1210257532277820)
/// [Pixel Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210341343812872)
enum DefaultBrowserAndDockPromptPixelEvent: PixelKitEventV2, Hashable {
    private enum ParameterKey {
        static let contentType = "contentType"
        static let numberOfBannersShown = "numberOfBannersShown"
    }

    /// Event Trigger: The SAD/ATT popover appears on screen.
    /// - Parameters:
    ///     - type: A hardcoded string with the following possible values (“set-as-default”, “add-to-dock”, “set-as-default-and-add-to-dock") representing the type of prompt.
    case popoverImpression(type: DefaultBrowserAndDockPromptType)
    /// Event Trigger: The primary action button of the SAD/ATT popover is clicked.
    /// - Parameters:
    ///     - type: A hardcoded string with the following possible values (“set-as-default”, “add-to-dock”, “set-as-default-and-add-to-dock") representing the type of prompt.
    case popoverConfirmButtonClicked(type: DefaultBrowserAndDockPromptType)
    /// Event Trigger: The “Not Now” button of the SAD/ATT popover is clicked.
    /// - Parameters:
    ///     - type: A hardcoded string with the following possible values (“set-as-default”, “add-to-dock”, “set-as-default-and-add-to-dock") representing the type of prompt.
    case popoverCloseButtonClicked(type: DefaultBrowserAndDockPromptType)
    /// Event Trigger: The SAD/ATT banner appears on screen.
    /// - Parameters:
    ///     - type: A hardcoded string with the following possible values (“set-as-default”, “add-to-dock”, “set-as-default-and-add-to-dock") representing the type of prompt.
    ///     - numberOfBannersShown: The number of banner that users have seen before clicking the confirm action.
    case bannerImpression(type: DefaultBrowserAndDockPromptType, numberOfBannersShown: String)
    /// Event Trigger: The primary action button of the SAD/ATT banner is clicked.
    /// - Parameters:
    ///     - type: A hardcoded string with the following possible values (“set-as-default”, “add-to-dock”, “set-as-default-and-add-to-dock") representing the type of prompt.
    ///     - numberOfBannersShown: The number of banner that users have seen before clicking the confirm action.
    case bannerConfirmButtonClicked(type: DefaultBrowserAndDockPromptType, numberOfBannersShown: String)
    /// Event Trigger: The “x” button of the SAD/ATT banner is clicked.
    /// - Parameters:
    ///     - type: A hardcoded string with the following possible values (“set-as-default”, “add-to-dock”, “set-as-default-and-add-to-dock") representing the type of prompt.
    case bannerCloseButtonClicked(type: DefaultBrowserAndDockPromptType)
    /// Event Trigger: The “Don't ask again” button of the SAD/ATT banner is clicked.
    /// - Parameters:
    ///     - type: A hardcoded string with the following possible values (“set-as-default”, “add-to-dock”, “set-as-default-and-add-to-dock") representing the type of prompt.
    case bannerNeverAskAgainButtonClicked(type: DefaultBrowserAndDockPromptType)

    var error: (any Error)? {
        nil
    }

    var name: String {
        switch self {
        case .popoverImpression:
            "m_mac_set-as-default-add-to-dock_popover-shown"
        case .popoverConfirmButtonClicked:
            "m_mac_set-as-default-add-to-dock_popover-confirm-action"
        case .popoverCloseButtonClicked:
            "m_mac_set-as-default-add-to-dock_popover-cancel-action"
        case .bannerImpression:
            "m_mac_set-as-default-add-to-dock_banner-shown"
        case .bannerConfirmButtonClicked:
            "m_mac_set-as-default-add-to-dock_banner-confirm-action"
        case .bannerCloseButtonClicked:
            "m_mac_set-as-default-add-to-dock_banner-cancel-action"
        case .bannerNeverAskAgainButtonClicked:
            "m_mac_set-as-default-add-to-dock_banner-never-ask-again-action"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case let .popoverImpression(type):
            [ParameterKey.contentType: type.promptTypeDescription]
        case let.popoverConfirmButtonClicked(type):
            [ParameterKey.contentType: type.promptTypeDescription]
        case let .popoverCloseButtonClicked(type):
            [ParameterKey.contentType: type.promptTypeDescription]
        case
            let .bannerImpression(type, numberOfBannersShown),
            let .bannerConfirmButtonClicked(type, numberOfBannersShown):
            [
                ParameterKey.contentType: type.promptTypeDescription,
                ParameterKey.numberOfBannersShown: String(numberOfBannersShown)
            ]
        case let .bannerCloseButtonClicked(type):
            [ParameterKey.contentType: type.promptTypeDescription]
        case let .bannerNeverAskAgainButtonClicked(type):
            [ParameterKey.contentType: type.promptTypeDescription]
        }
    }
}

// MARK: - Debug Pixels

/// An enum defining the debug pixel events for SAD/ATT prompts.
/// > Related links:
/// [Pixel Definition](https://app.asana.com/1/137249556945/project/1206329551987282/task/1210257532277820)
/// [Pixel Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210341343812872)
enum DefaultBrowserAndDockPromptDebugPixelEvent: PixelKitEventV2 {
    /// Trigger Event: The popover seen date fails to save.
    case failedToSavePopoverSeenDate
    /// Trigger Event: The popover seen date fails to retrieve.
    case failedToRetrievePopoverSeenDate
    /// Trigger Event: The banner seen date fails to save.
    case failedToSaveBannerSeenDate
    /// Trigger Event: The banner seen date fails to retrieve.
    case failedToRetrieveBannerSeenDate
    /// Trigger Event: The number of banners seen fails to save.
    case failedToSaveNumberOfBannerShown
    /// Trigger Event: The number of banners seen fails to retrieve.
    case failedToRetrieveNumberOfBannerShown
    /// Trigger Event: The permanently dismissed flag fails to save.
    case failedToSaveBannerPermanentlyDismissedValue
    /// Trigger Event: The permanently dismissed flag fails to retrieve.
    case failedToRetrieveBannerPermanentlyDismissedValue

    var error: (any Error)? {
        nil
    }

    var name: String {
        switch self {
        /// Event Trigger: Failed to write the popover seen date value in the KeyValue store.
        case .failedToSavePopoverSeenDate:
            "m_mac_debug_set-as-default-add-to-dock_failed-to-save-popover-seen-date"
        /// Event Trigger: Failed to retrieve the popover seen date value in the KeyValue store.
        case .failedToRetrievePopoverSeenDate:
            "m_mac_debug_set-as-default-add-to-dock_failed-to-retrieve-popover-seen-date"
        /// Event Trigger: Failed to write the banner seen date value in the KeyValue store.
        case .failedToSaveBannerSeenDate:
            "m_mac_debug_set-as-default-add-to-dock_failed-to-save-banner-seen-date"
        /// Event Trigger: Failed to retrieve the banner seen date value in the KeyValue store.
        case .failedToRetrieveBannerSeenDate:
            "m_mac_debug_set-as-default-add-to-dock_failed-to-retrieve-banner-seen-date"
        /// Event Trigger: Failed to write the number of banner seen value in the KeyValue store.
        case .failedToSaveNumberOfBannerShown:
            "m_mac_debug_set-as-default-add-to-dock_failed-to-save-number-of-banner-shown"
        /// Event Trigger: Failed to retrieve the number of banner seen value in the KeyValue store.
        case .failedToRetrieveNumberOfBannerShown:
            "m_mac_debug_set-as-default-add-to-dock_failed-to-retrieve-number-of-banner-shown"
        /// Event Trigger: Failed to write the permanently dismissed flag value in the KeyValue store.
        case .failedToSaveBannerPermanentlyDismissedValue:
            "m_mac_debug_set-as-default-add-to-dock_failed-to-save-banner-permanently-dismissed-value"
        /// Event Trigger: Failed to retrieve the permanently dismissed flag value in the KeyValue store.
        case .failedToRetrieveBannerPermanentlyDismissedValue:
            "m_mac_debug_set-as-default-add-to-dock_failed-to-retrieve-banner-permanently-dismissed-value"
        }
    }

    var parameters: [String: String]? {
        nil
    }

}

// MARK: - Helpers

private extension DefaultBrowserAndDockPromptType {

    var promptTypeDescription: String {
        switch self {
        case .setAsDefaultPrompt:
            return "set-as-default"
        case .addToDockPrompt:
            return "add-to-dock"
        case .bothDefaultBrowserAndDockPrompt:
            return "set-as-default-and-add-to-dock"
        }
    }
}
