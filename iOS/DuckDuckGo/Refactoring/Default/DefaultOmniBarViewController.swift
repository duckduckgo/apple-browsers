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
import Core

final class DefaultOmniBarViewController: OmniBarViewController {
    private lazy var omniBarView: DefaultOmniBarView = DefaultOmniBarView.create()

    override func loadView() {
        view = omniBarView
    }

    override func updateAccessoryType(_ type: OmniBarAccessoryType) {
        super.updateAccessoryType(type)
        self.updatePadding()
    }

    override func updateInterface(from oldState: any OmniBarState, to state: any OmniBarState) {
        omniBarView.searchFieldContainer.adjustTextFieldOffset(for: state)

        super.updateInterface(from: oldState, to: state)

        omniBarView.searchContainerCenterConstraint.isActive = state.hasLargeWidth
        omniBarView.searchContainerMaxWidthConstraint.isActive = state.hasLargeWidth
        omniBarView.leftButtonsSpacingConstraint.constant = state.hasLargeWidth ? 24 : 0
        omniBarView.rightButtonsSpacingConstraint.constant = state.hasLargeWidth ? 24 : trailingConstraintValueForSmallWidth

        if state.showVoiceSearch && state.showClear {
            omniBarView.searchStackContainer.setCustomSpacing(13, after: omniBarView.voiceSearchButton)
        }

        if oldState.showAccessoryButton != state.showAccessoryButton ||
            oldState.hasLargeWidth != state.hasLargeWidth {
            updatePadding()
        }
    }

    // MARK: - Private

    private var trailingConstraintValueForSmallWidth: CGFloat {
        if state.showAccessoryButton || state.showSettings {
            return 14
        } else {
            return 4
        }
    }

    /// When a setting that affects the accessory button is modified, `refreshState` is called.
    /// This requires updating the padding to ensure consistent layout.
    private func updatePadding() {
        omniBarView.omniBarLeadingConstraint.constant = (state.hasLargeWidth ? 24 : 8)
        omniBarView.omniBarTrailingConstraint.constant = (state.hasLargeWidth ? 24 : trailingConstraintValueForSmallWidth)
    }
}
