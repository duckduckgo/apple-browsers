//
//  SERPSettingsUserScriptDelegate.swift
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

/// Delegate protocol for handling SERP settings navigation requests.
///
/// Implementers of this protocol respond to user navigation actions initiated
/// from the SERP settings page, presenting the appropriate native settings screens.
///
/// ## Typical Implementation
///
/// The delegate is usually implemented by a view controller or coordinator
/// that can present settings screens and manage navigation:
///
/// ```swift
/// extension MyViewController: SERPSettingsUserScriptDelegate {
///     func serpSettingsUserScriptDidRequestToCloseTabAndOpenPrivacySettings(_ userScript: SERPSettingsUserScript) {
///         closeCurrentTab()
///         settingsCoordinator.showPrivacySettings()
///     }
///     
///     func serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript) {
///         settingsCoordinator.showAISettings()
///     }
/// }
/// ```
public protocol SERPSettingsUserScriptDelegate: AnyObject {

    /// Requests closing the current tab and opening privacy search settings.
    ///
    /// Called when the user clicks a "return to privacy settings" link on the SERP.
    /// The implementer should:
    /// 1. Close the current browser tab/window (if needed)
    /// 2. Navigate to the privacy search settings screen
    ///
    /// ## Use Case
    ///
    /// User navigates from Privacy Settings → SERP Settings → (clicks return link)
    ///
    /// - Parameter userScript: The user script instance making the request
    func serpSettingsUserScriptDidRequestToOpenPrivacySettings(_ userScript: SERPSettingsUserScript)

    /// Requests opening AI features settings
    ///
    /// Called when the user clicks a direct link to AI features settings on the SERP.
    /// The implementer should navigate to the AI features settings screen, closes the tab if needed.
    ///
    /// ## Use Case
    ///
    /// User clicks "Configure Duck.ai" link directly from SERP
    ///
    /// - Parameter userScript: The user script instance making the request
    func serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript)
}
