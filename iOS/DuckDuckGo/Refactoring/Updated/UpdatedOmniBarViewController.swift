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

final class UpdatedOmniBarViewController: OmniBarViewController {

    private lazy var omniBarView = UpdatedOmniBarView.create()

    override func loadView() {
        view = omniBarView
    }

    // MARK: - Initialization

    override func viewDidLoad() {
        super.viewDidLoad()

    }

    override func updateInterface(from oldState: any OmniBarState, to state: any OmniBarState) {
        super.updateInterface(from: oldState, to: state)

        omniBarView.isUsingCompactLayout = !state.hasLargeWidth
    }

    override func cancelAllAnimations() {
        // TODO: Implement or remove
    }

    override func updatePrivacyIcon(for privacyInfo: PrivacyInfo?) {

    }

    override func hidePrivacyIcon() {

    }

    override func resetPrivacyIcon(for url: URL?) {
        
    }

    override func dismissOnboardingPrivacyIconAnimation() {

    }

    override func startTrackersAnimation(_ privacyInfo: PrivacyInfo, forDaxDialog: Bool) {
        
    }

    override func textFieldDidBeginEditing(_ textField: UITextField) {
        super.textFieldDidBeginEditing(textField)

        omniBarView.layoutIfNeeded()
        omniBarView.isActiveState = true
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.25, delay: 0.0, options: [.curveEaseOut]) {
            self.omniBarView.layoutIfNeeded()
        }
    }

    override func textFieldDidEndEditing(_ textField: UITextField) {
        super.textFieldDidEndEditing(textField)

        omniBarView.layoutIfNeeded()
        omniBarView.isActiveState = false
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.25, delay: 0.0, options: [.curveEaseOut]) {
            self.omniBarView.layoutIfNeeded()
        }
    }
}
