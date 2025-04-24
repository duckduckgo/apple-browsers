//
//  OmniBarView.swift
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

protocol OmniBarView: UIView, OmniBarStatusUpdateable {

    var text: String? { get set }
    var expectedHeight: CGFloat { get }

    // Original omnibar accessors
    var textField: TextFieldWithInsets! { get }
    var accessoryType: OmniBarAccessoryType { get set }
    var privacyInfoContainer: PrivacyInfoContainerView! { get }
    var notificationContainer: OmniBarNotificationContainerView! { get }
    var searchContainer: UIView! { get }

    var searchLoupe: UIView! { get }
    var dismissButton: UIButton! { get }

    var backButton: UIButton! { get }
    var forwardButton: UIButton! { get }
    var settingsButton: UIButton! { get }
    var cancelButton: UIButton! { get }
    var bookmarksButton: UIButton! { get }
    var accessoryButton: UIButton! { get }
    var menuButton: UIButton! { get }
    var refreshButton: UIButton! { get }

    var leftIconContainerView: UIView! { get }

    var customIconView: UIImageView { get }
    var clearButton: UIButton! { get }

    func showSeparator()
    func hideSeparator()
    func moveSeparatorToTop()
    func moveSeparatorToBottom()
    // -- end

    var progressView: ProgressView? { get }

    var privacyIconView: UIView? { get }

    var searchContainerWidth: CGFloat { get }

    var menuButtonContent: MenuButton { get }

    var onTextEntered: (() -> Void)? { get set }
    var onVoiceSearchButtonPressed: (() -> Void)? { get set }
    var onAbortButtonPressed: (() -> Void)? { get set }
    var onClearButtonPressed: (() -> Void)? { get set }
    var onPrivacyIconPressed: (() -> Void)? { get set }
    var onMenuButtonPressed: (() -> Void)? { get set }
    var onTrackersViewPressed: (() -> Void)? { get set }
    var onSettingsButtonPressed: (() -> Void)? { get set }
    var onCancelPressed: (() -> Void)? { get set }
    var onRefreshPressed: (() -> Void)? { get set }
    var onBackPressed: (() -> Void)? { get set }
    var onForwardPressed: (() -> Void)? { get set }
    var onBookmarksPressed: (() -> Void)? { get set }
    var onAccessoryPressed: (() -> Void)? { get set }
    var onDismissPressed: (() -> Void)? { get set }

    var onSettingsLongPress: (() -> Void)? { get set }
    var onAccessoryLongPress: (() -> Void)? { get set }

    // static function is needed to allow creation of DefaultOmniBarView from xib
    static func create() -> Self
}

protocol OmniBarStatusUpdateable: AnyObject {
    var isPrivacyInfoContainerHidden: Bool { get set }
    var isClearButtonHidden: Bool { get set }
    var isMenuButtonHidden: Bool { get set }
    var isSettingsButtonHidden: Bool { get set }
    var isCancelButtonHidden: Bool { get set }
    var isRefreshButtonHidden: Bool { get set }
    var isVoiceSearchButtonHidden: Bool { get set }
    var isAbortButtonHidden: Bool { get set }
    var isBackButtonHidden: Bool { get set }
    var isForwardButtonHidden: Bool { get set }
    var isBookmarksButtonHidden: Bool { get set }
    var isAccessoryButtonHidden: Bool { get set }
    var isSearchLoupeHidden: Bool { get set }
    var isDismissButtonHidden: Bool { get set }
}
