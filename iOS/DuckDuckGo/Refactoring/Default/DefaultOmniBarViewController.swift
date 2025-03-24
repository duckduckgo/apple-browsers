//
//  DefaultOmniBarViewController.swift
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
import PrivacyDashboard

final class DefaultOmniBarViewController: UIViewController, OmniBar {
    private(set) lazy var omniBarView: DefaultOmniBarView = {
        DefaultOmniBarView.loadFromXib(dependencies: dependencies)
    }()

    private let dependencies: OmnibarDependencyProvider

    // MARK: - OmniBar conformance

    var barView: OmniBarView {
        omniBarView
    }

    var omniDelegate: OmniBarDelegate? {
        get { omniBarView.omniDelegate }
        set { omniBarView.omniDelegate = newValue }
    }
    var isTextFieldEditing: Bool { omniBarView.textField.isFirstResponder }

    var isBackButtonEnabled: Bool {
        get { omniBarView.backButton.isEnabled }
        set { omniBarView.backButton.isEnabled = newValue }
    }

    var isForwardButtonEnabled: Bool {
        get { omniBarView.forwardButton.isEnabled }
        set { omniBarView.forwardButton.isEnabled = newValue }
    }

    var text: String? {
        get { omniBarView.textField.text }
        set { omniBarView.textField.text = newValue }
    }

    // MARK: -

    init(dependencies: OmnibarDependencyProvider) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = omniBarView
    }

    // MARK: - OmniBar conformance

    func showSeparator() {
        omniBarView.showSeparator()
    }

    func hideSeparator() {
        omniBarView.hideSeparator()
    }

    func moveSeparatorToTop() {
        omniBarView.moveSeparatorToTop()
    }

    func moveSeparatorToBottom() {
        omniBarView.moveSeparatorToBottom()
    }

    func startBrowsing() {
        omniBarView.startBrowsing()
    }

    func stopBrowsing() {
        omniBarView.stopBrowsing()
    }

    func startLoading() {
        omniBarView.startLoading()
    }

    func stopLoading() {
        omniBarView.stopLoading()
    }

    func cancel() {
        omniBarView.cancel()
    }

    func updateQuery(_ query: String?) {
        text = query
        omniBarView.textDidChange()
    }

    func beginEditing() {
        omniBarView.textField.becomeFirstResponder()
    }

    func endEditing() {
        omniBarView.textField.resignFirstResponder()
    }

    func refreshText(forUrl url: URL?, forceFullURL: Bool) {
        omniBarView.refreshText(forUrl: url, forceFullURL: forceFullURL)
    }

    func enterPhoneState() {
        omniBarView.enterPhoneState()
    }

    func enterPadState() {
        omniBarView.enterPadState()
    }

    func removeTextSelection() {
        omniBarView.removeTextSelection()
    }

    func selectTextToEnd(_ offset: Int) {
        omniBarView.selectTextToEnd(offset)
    }

    func updateAccessoryType(_ type: OmniBarAccessoryType) {
        omniBarView.updateAccessoryType(type)
    }

    func showOrScheduleCookiesManagedNotification(isCosmetic: Bool) {
        omniBarView.showOrScheduleCookiesManagedNotification(isCosmetic: isCosmetic)
    }

    func showOrScheduleOnboardingPrivacyIconAnimation() {
        omniBarView.showOrScheduleOnboardingPrivacyIconAnimation()
    }

    func dismissOnboardingPrivacyIconAnimation() {
        omniBarView.dismissOnboardingPrivacyIconAnimation()
    }

    func startTrackersAnimation(_ privacyInfo: PrivacyDashboard.PrivacyInfo, forDaxDialog: Bool) {
        omniBarView.startTrackersAnimation(privacyInfo, forDaxDialog: forDaxDialog)
    }

    func updatePrivacyIcon(for privacyInfo: PrivacyDashboard.PrivacyInfo?) {
        omniBarView.updatePrivacyIcon(for: privacyInfo)
    }

    func hidePrivacyIcon() {
        omniBarView.hidePrivacyIcon()
    }

    func resetPrivacyIcon(for url: URL?) {
        omniBarView.resetPrivacyIcon(for: url)
    }

    func cancelAllAnimations() {
        omniBarView.cancelAllAnimations()
    }

    func completeAnimationForDaxDialog() {
        omniBarView.completeAnimationForDaxDialog()
    }
}
