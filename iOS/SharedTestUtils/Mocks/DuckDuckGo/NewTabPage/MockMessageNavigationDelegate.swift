//
//  MockMessageNavigationDelegate.swift
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

@testable import DuckDuckGo
import DDGSync

class MockMessageNavigationDelegate: MessageNavigationDelegate {
    private(set) var didCallSegueToAIChatSettings: Bool = false
    private(set) var capturedAIChatOpenedFromSERPSettingsButton: Bool?
    private(set) var didCallSegueToSettings: Bool = false
    private(set) var didCallSegueToSettingsAppearance: Bool = false
    private(set) var didCallSegueToFeedback: Bool = false
    private(set) var didCallSegueToSettingsSync: Bool = false
    private(set) var didCallSegueToPIR: Bool = false
    private(set) var capturedSettingsSyncSource: String?
    private(set) var capturedSettingsSyncPairingInfo: PairingInfo?

    private(set) var didCallSegueToImportPasswords: Bool = false

    private(set) var capturedPresentationStyle: PresentationContext.Style?

    func segueToSettingsAIChat(openedFromSERPSettingsButton: Bool, presentationStyle: PresentationContext.Style) {
        didCallSegueToAIChatSettings = true
        capturedAIChatOpenedFromSERPSettingsButton = openedFromSERPSettingsButton
        capturedPresentationStyle = presentationStyle
    }

    func segueToSettings(presentationStyle: PresentationContext.Style) {
        didCallSegueToSettings = true
        capturedPresentationStyle = presentationStyle
    }

    func segueToFeedback(presentationStyle: PresentationContext.Style) {
        didCallSegueToFeedback = true
        capturedPresentationStyle = presentationStyle
    }

    func segueToSettingsSync(with source: String?, pairingInfo: PairingInfo?, presentationStyle: PresentationContext.Style) {
        didCallSegueToSettingsSync = true
        capturedSettingsSyncSource = source
        capturedSettingsSyncPairingInfo = pairingInfo
        capturedPresentationStyle = presentationStyle
    }

    func segueToImportPasswords(presentationStyle: PresentationContext.Style) {
        didCallSegueToImportPasswords = true
        capturedPresentationStyle = presentationStyle
    }

    func segueToSettingsAppearance(presentationStyle: PresentationContext.Style) {
        didCallSegueToSettingsAppearance = true
        capturedPresentationStyle = presentationStyle
    }

    func segueToPIR(presentationStyle: DuckDuckGo.PresentationContext.Style) {
        didCallSegueToPIR = true
        capturedPresentationStyle = presentationStyle
    }
}
