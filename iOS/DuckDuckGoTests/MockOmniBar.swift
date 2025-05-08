//
//  MockOmniBar.swift
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

@testable import DuckDuckGo

final class MockOmniBar: OmniBar {
    var mockBarView = MockOmniBarView()
    var barView: any DuckDuckGo.OmniBarView {
        mockBarView
    }
    var isBackButtonEnabled: Bool = false
    var isForwardButtonEnabled: Bool = false
    var omniDelegate: (any DuckDuckGo.OmniBarDelegate)?
    var isTextFieldEditing: Bool = false
    var text: String?
    
    func updateQuery(_ query: String?) { }
    func refreshText(forUrl url: URL?, forceFullURL: Bool) { }
    func beginEditing() { }
    func endEditing() { }
    func showSeparator() { }
    func hideSeparator() { }
    func moveSeparatorToTop() { }
    func moveSeparatorToBottom() { }
    func useSmallTopSpacing() { }
    func useRegularTopSpacing() { }
    func enterPhoneState() { }
    func enterPadState() { }
    func startBrowsing() { }
    func stopBrowsing() { }
    func startLoading() { }
    func stopLoading() { }
    func cancel() { }
    func removeTextSelection() { }
    func selectTextToEnd(_ offset: Int) { }
    func updateAccessoryType(_ type: DuckDuckGo.OmniBarAccessoryType) { }
    func showOrScheduleCookiesManagedNotification(isCosmetic: Bool) { }
    func showOrScheduleOnboardingPrivacyIconAnimation() { }
    func dismissOnboardingPrivacyIconAnimation() { }
    func startTrackersAnimation(_ privacyInfo: PrivacyDashboard.PrivacyInfo, forDaxDialog: Bool) { }
    func updatePrivacyIcon(for privacyInfo: PrivacyDashboard.PrivacyInfo?) { }
    func hidePrivacyIcon() { }
    func resetPrivacyIcon(for url: URL?) { }
    func cancelAllAnimations() { }
    func completeAnimationForDaxDialog() { }
    
    final class MockOmniBarView: UIView, OmniBarView {
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        init() {
            super.init(frame: .zero)
        }
        
        var text: String?
        static let expectedHeight: CGFloat = 52
        var expectedHeight: CGFloat = MockOmniBarView.expectedHeight
        var textField: DuckDuckGo.TextFieldWithInsets!
        var accessoryType: DuckDuckGo.OmniBarAccessoryType = .chat
        var privacyInfoContainer: DuckDuckGo.PrivacyInfoContainerView!
        var notificationContainer: DuckDuckGo.OmniBarNotificationContainerView!
        var searchContainer: UIView! = UIView()
        var searchLoupe: UIView! = UIView()
        var dismissButton: UIButton! = UIButton()
        var backButton: UIButton! = UIButton()
        var forwardButton: UIButton! = UIButton()
        var settingsButton: UIButton! = UIButton()
        var cancelButton: UIButton! = UIButton()
        var bookmarksButton: UIButton! = UIButton()
        var accessoryButton: UIButton! = UIButton()
        var menuButton: UIButton! = UIButton()
        var refreshButton: UIButton! = UIButton()
        var leftIconContainerView: UIView! = UIView()
        var customIconView: UIImageView = UIImageView()
        var clearButton: UIButton! = UIButton()
        
        func showSeparator() { }
        func hideSeparator() { }
        func moveSeparatorToTop() { }
        func moveSeparatorToBottom() { }
        
        var progressView: DuckDuckGo.ProgressView?
        var privacyIconView: UIView?
        var searchContainerWidth: CGFloat = 0
        var menuButtonContent: DuckDuckGo.MenuButton = .init()
        var onTextEntered: (() -> Void)?
        var onVoiceSearchButtonPressed: (() -> Void)?
        var onAbortButtonPressed: (() -> Void)?
        var onClearButtonPressed: (() -> Void)?
        var onPrivacyIconPressed: (() -> Void)?
        var onMenuButtonPressed: (() -> Void)?
        var onTrackersViewPressed: (() -> Void)?
        var onSettingsButtonPressed: (() -> Void)?
        var onCancelPressed: (() -> Void)?
        var onRefreshPressed: (() -> Void)?
        var onBackPressed: (() -> Void)?
        var onForwardPressed: (() -> Void)?
        var onBookmarksPressed: (() -> Void)?
        var onAccessoryPressed: (() -> Void)?
        var onDismissPressed: (() -> Void)?
        var onSettingsLongPress: (() -> Void)?
        var onAccessoryLongPress: (() -> Void)?
        
        static func create() -> Self {
            Self.init()
        }
        
        var isPrivacyInfoContainerHidden: Bool = true
        var isClearButtonHidden: Bool = true
        var isMenuButtonHidden: Bool = true
        var isSettingsButtonHidden: Bool = true
        var isCancelButtonHidden: Bool = true
        var isRefreshButtonHidden: Bool = true
        var isVoiceSearchButtonHidden: Bool = true
        var isAbortButtonHidden: Bool = true
        var isBackButtonHidden: Bool = true
        var isForwardButtonHidden: Bool = true
        var isBookmarksButtonHidden: Bool = true
        var isAccessoryButtonHidden: Bool = true
        var isSearchLoupeHidden: Bool = true
        var isDismissButtonHidden: Bool = true
        
    }
}
