//
//  UpdatedOmniBarViewController.swift
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

final class UpdatedOmniBarViewController: UIViewController, OmniBar {

    private var omniBarView: UpdatedOmniBarView!
    private let dependencies: OmnibarDependencyProvider

    var barView: any OmniBarView {
        loadViewIfNeeded()
        return omniBarView
    }

    var isBackButtonEnabled: Bool = false

    var isForwardButtonEnabled: Bool = false

    weak var omniDelegate: (any OmniBarDelegate)?
    
    var isTextFieldEditing: Bool {
        omniBarView.textField.isFirstResponder
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
        omniBarView = UpdatedOmniBarView()

        view = omniBarView
    }

    func updateQuery(_ query: String?) {
        omniBarView.textField.text = query
    }
    
    func refreshText(forUrl url: URL?, forceFullURL: Bool) {
        omniBarView.textField.text = url?.absoluteString
    }
    
    func beginEditing() {
        omniBarView.textField.becomeFirstResponder()
    }
    
    func endEditing() {
        omniBarView.textField.resignFirstResponder()
    }
    
    func showSeparator() {
        // no-op
    }
    
    func hideSeparator() {
        // no-op
    }
    
    func moveSeparatorToTop() {
        // no-op
    }
    
    func moveSeparatorToBottom() {
        // no-op
    }
    
    func enterPhoneState() {

    }
    
    func enterPadState() {

    }

    func startBrowsing() {

    }
    
    func stopBrowsing() {

    }
    
    func startLoading() {

    }
    
    func stopLoading() {

    }
    
    func cancel() {

    }
    
    func removeTextSelection() {

    }
    
    func selectTextToEnd(_ offset: Int) {

    }
    
    func updateAccessoryType(_ type: OmniBarAccessoryType) {

    }
    
    func showOrScheduleCookiesManagedNotification(isCosmetic: Bool) {

    }
    
    func showOrScheduleOnboardingPrivacyIconAnimation() {

    }
    
    func dismissOnboardingPrivacyIconAnimation() {

    }
    
    func startTrackersAnimation(_ privacyInfo: PrivacyDashboard.PrivacyInfo, forDaxDialog: Bool) {

    }
    
    func updatePrivacyIcon(for privacyInfo: PrivacyDashboard.PrivacyInfo?) {

    }
    
    func hidePrivacyIcon() {

    }
    
    func resetPrivacyIcon(for url: URL?) {

    }
    
    func cancelAllAnimations() {

    }
    
    func completeAnimationForDaxDialog() {

    }
}
