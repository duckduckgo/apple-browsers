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

protocol OmniBarView: UIView {

    var text: String? { get set }

    var progressView: ProgressView? { get }
    var searchContainerView: UIView { get }
    var bookmarksButtonView: UIButton { get }
    var accessoryButtonView: UIButton { get }
    var menuButtonView: UIButton { get }

    var privacyIconView: UIView? { get }

    var backButtonMenu: UIMenu? { get set }
    var forwardButtonMenu: UIMenu? { get set }

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
