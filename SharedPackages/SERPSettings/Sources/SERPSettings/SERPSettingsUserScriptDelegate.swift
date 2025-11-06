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

    /// Requests closing the current tab.
    ///
    /// Called when the user clicks a "Save & Exit" link on the SERP (either on Privacy or AI settings) when coming from native Settings.
    /// The implementer should close the current browser tab/window (if needed)
    /// This is `macOS` only. `iOS` do not show the 'Save & Exit' button
    ///
    /// ## Use Case
    ///
    /// User navigates from Native Settings -> SERP Settings (either Privacy or AI) → Taps 'Save & Exit' (clicks return link)
    ///
    /// - Parameter userScript: The user script instance making the request
    func serpSettingsUserScriptDidRequestToCloseTab(_ userScript: SERPSettingsUserScript)

    /// Requests opening AI features settings
    ///
    /// Called when the user clicks 'Open Duck.ai Settings' from the SERP AI Features Settings.
    /// The implementer should navigate to the AI features settings screen, closes the tab if needed.
    ///
    /// ## Use Case
    ///
    /// User clicks "Open Duck.ai Settings" link directly from SERP
    ///
    /// - Parameter userScript: The user script instance making the request
    func serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript)
}
