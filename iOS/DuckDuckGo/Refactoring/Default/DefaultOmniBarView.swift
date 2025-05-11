//
//  DefaultOmniBarView.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import Common
import UIKit
import Core
import PrivacyDashboard
import DesignResourcesKit
import DuckPlayer
import os.log
import BrowserServicesKit

extension DefaultOmniBarView: NibLoading {}

public enum OmniBarIcon: String {
    case duckPlayer = "DuckPlayerURLIcon"
    case specialError = "Globe-24"
}

final class DefaultOmniBarView: UIView {

    public static let didLayoutNotification = Notification.Name("com.duckduckgo.app.OmniBarDidLayout")
    
    @IBOutlet weak var searchLoupe: UIView!
    @IBOutlet weak var searchContainer: UIView!
    @IBOutlet weak var searchStackContainer: UIStackView!
    @IBOutlet weak var searchFieldContainer: SearchFieldContainerView!
    @IBOutlet weak var privacyInfoContainer: PrivacyInfoContainerView!
    @IBOutlet weak var notificationContainer: OmniBarNotificationContainerView!
    @IBOutlet weak var textField: TextFieldWithInsets!
    @IBOutlet weak var editingBackground: RoundedRectangleView!
    @IBOutlet weak var clearButton: UIButton!
    @IBOutlet weak var menuButton: UIButton!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var separatorView: UIView!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var refreshButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var voiceSearchButton: UIButton!
    @IBOutlet weak var abortButton: UIButton!

    @IBOutlet weak var bookmarksButton: UIButton!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var forwardButton: UIButton!
    @IBOutlet weak var accessoryButton: UIButton!

    private(set) var menuButtonContent = MenuButton()

    // Don't use weak because adding/removing them causes them to go away
    @IBOutlet var separatorHeightConstraint: NSLayoutConstraint!
    @IBOutlet var leftButtonsSpacingConstraint: NSLayoutConstraint!
    @IBOutlet var rightButtonsSpacingConstraint: NSLayoutConstraint!
    @IBOutlet var searchContainerCenterConstraint: NSLayoutConstraint!
    @IBOutlet var searchContainerMaxWidthConstraint: NSLayoutConstraint!
    @IBOutlet var omniBarLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var omniBarTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var separatorToBottom: NSLayoutConstraint!

    @IBOutlet weak var dismissButton: UIButton!

    /// A container view designed to maintain visual consistency among various items within this space.
    /// Additionally, it facilitates smooth animations for the elements it contains.
    @IBOutlet weak var leftIconContainerView: UIView!

    let expectedHeight: CGFloat = DefaultOmniBarView.expectedHeight
    static let expectedHeight: CGFloat = 52

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
    var onSharePressed: (() -> Void)?
    var onBackPressed: (() -> Void)?
    var onForwardPressed: (() -> Void)?
    var onBookmarksPressed: (() -> Void)?
    var onAccessoryPressed: (() -> Void)?
    var onDismissPressed: (() -> Void)?
    var onSettingsLongPress: (() -> Void)?
    var onAccessoryLongPress: (() -> Void)?

    var accessoryType: OmniBarAccessoryType = .chat {
        didSet {
            switch accessoryType {
            case .chat:
                accessoryButton.setImage(UIImage(named: "AIChat-24"), for: .normal)
            }
        }
    }

    // Set up a view to add a custom icon to the Omnibar
    private(set) var customIconView: UIImageView = UIImageView(frame: CGRect(x: 4, y: 8, width: 26, height: 26))

    static func create() -> DefaultOmniBarView {
        DefaultOmniBarView.load(nibName: "OmniBar")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // Tests require this
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        configureMenuButton()
        configureSettingsLongPressButton()
        configureShareLongPressButton()

        configureSeparator()

        decorate()
    }

    private func configureSettingsLongPressButton() {
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleSettingsLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.7
        settingsButton.addGestureRecognizer(longPressGesture)
    }

    private func configureShareLongPressButton() {
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleShareLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.7
        accessoryButton.addGestureRecognizer(longPressGesture)
    }

    @objc private func handleSettingsLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onSettingsLongPress?()
        }
    }

    @objc private func handleShareLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onAccessoryLongPress?()
        }
    }

    private func configureMenuButton() {
        menuButton.addSubview(menuButtonContent)
        menuButton.isAccessibilityElement = true
        menuButton.accessibilityTraits = .button
    }

    private func configureSeparator() {
        separatorHeightConstraint.constant = 1.0 / UIScreen.main.scale
    }

    var textFieldBottomSpacing: CGFloat {
        return (bounds.size.height - (searchContainer.frame.origin.y + searchContainer.frame.size.height)) / 2.0
    }
    
    func showSeparator() {
        separatorView.isHidden = false
    }
    
    func hideSeparator() {
        separatorView.isHidden = true
    }

    func moveSeparatorToTop() {
        separatorToBottom.constant = frame.height
    }

    func moveSeparatorToBottom() {
        separatorToBottom.constant = 0
    }

    @IBAction private func onTextEntered(_ sender: Any) {
        onTextEntered?()
    }

    @IBAction private func onVoiceSearchButtonPressed(_ sender: UIButton) {
        onVoiceSearchButtonPressed?()
    }

    @IBAction private func onAbortButtonPressed(_ sender: Any) {
        onAbortButtonPressed?()
    }

    @IBAction private func onClearButtonPressed(_ sender: Any) {
        onClearButtonPressed?()
    }

    @IBAction private func onPrivacyIconPressed(_ sender: Any) {
        onPrivacyIconPressed?()
    }

    @IBAction private func onMenuButtonPressed(_ sender: UIButton) {
        onMenuButtonPressed?()
    }

    @IBAction private func onTrackersViewPressed(_ sender: Any) {
        onTrackersViewPressed?()
    }

    @IBAction private func onSettingsButtonPressed(_ sender: Any) {
        onSettingsButtonPressed?()
    }

    @IBAction private func onCancelPressed(_ sender: Any) {
        onCancelPressed?()
    }
    
    @IBAction private func onRefreshPressed(_ sender: Any) {
        onRefreshPressed?()
    }
    
    @IBAction private func onBackPressed(_ sender: Any) {
        onBackPressed?()
    }
    
    @IBAction private func onForwardPressed(_ sender: Any) {
        onForwardPressed?()
    }
    
    @IBAction private func onBookmarksPressed(_ sender: Any) {
        onBookmarksPressed?()
    }

    @IBAction private func onAccessoryPressed(_ sender: Any) {
        onAccessoryPressed?()
    }

    @IBAction private func onDismissPressed(_ sender: Any) {
        onDismissPressed?()
    }

    @IBAction private func onSharePressed(_ sender: Any) {
        onSharePressed?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        NotificationCenter.default.post(name: DefaultOmniBarView.didLayoutNotification, object: self)
    }
}

extension DefaultOmniBarView {
    
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        backgroundColor = theme.omniBarBackgroundColor
        tintColor = theme.barTintColor

        editingBackground?.backgroundColor = theme.searchBarBackgroundColor
        editingBackground?.borderColor = theme.searchBarBackgroundColor

        searchStackContainer?.tintColor = theme.barTintColor
        
        textField.textColor = theme.searchBarTextColor
        textField.tintColor = UIColor(designSystemColor: .accent)
        textField.keyboardAppearance = theme.keyboardAppearance
        clearButton.tintColor = UIColor(designSystemColor: .icons)
        voiceSearchButton.tintColor = UIColor(designSystemColor: .icons)
        
        searchLoupe.tintColor = UIColor(designSystemColor: .iconsSecondary)
        cancelButton.setTitleColor(theme.barTintColor, for: .normal)
    }
}

extension DefaultOmniBarView: OmniBarView {

    var text: String? {
        get { textField.text }
        set { textField.text = newValue }
    }
    
    var searchContainerWidth: CGFloat {
        // 24 is accomodating for the padding
        searchStackContainer.frame.width + 24
    }

    var privacyIconView: UIView? {
        privacyInfoContainer.privacyIcon
    }

    var progressView: ProgressView? {
        nil
    }
}

// MARK: - OmniBarStatusUpdateable conformance
extension DefaultOmniBarView {

    var isPrivacyInfoContainerHidden: Bool {
        get { privacyInfoContainer.isHidden }
        set { setVisibility(privacyInfoContainer, hidden: newValue) }
    }

    var isClearButtonHidden: Bool {
        get { clearButton.isHidden }
        set { setVisibility(clearButton, hidden: newValue) }
    }

    var isMenuButtonHidden: Bool {
        get { menuButton.isHidden }
        set { setVisibility(menuButton, hidden: newValue) }
    }

    var isSettingsButtonHidden: Bool {
        get { settingsButton.isHidden }
        set { setVisibility(settingsButton, hidden: newValue) }
    }

    var isCancelButtonHidden: Bool {
        get { cancelButton.isHidden }
        set { setVisibility(cancelButton, hidden: newValue) }
    }

    var isRefreshButtonHidden: Bool {
        get { refreshButton.isHidden }
        set { setVisibility(refreshButton, hidden: newValue) }
    }

    var isShareButtonHidden: Bool {
        get { shareButton.isHidden }
        set { setVisibility(shareButton, hidden: newValue) }
    }

    var isVoiceSearchButtonHidden: Bool {
        get { voiceSearchButton.isHidden }
        set { setVisibility(voiceSearchButton, hidden: newValue) }
    }

    var isAbortButtonHidden: Bool {
        get { abortButton.isHidden }
        set { setVisibility(abortButton, hidden: newValue) }
    }

    var isBackButtonHidden: Bool {
        get { backButton.isHidden }
        set { setVisibility(backButton, hidden: newValue) }
    }

    var isForwardButtonHidden: Bool {
        get { forwardButton.isHidden }
        set { setVisibility(forwardButton, hidden: newValue) }
    }

    var isBookmarksButtonHidden: Bool {
        get { bookmarksButton.isHidden }
        set { setVisibility(bookmarksButton, hidden: newValue) }
    }

    var isAccessoryButtonHidden: Bool {
        get { accessoryButton.isHidden }
        set { setVisibility(accessoryButton, hidden: newValue) }
    }

    var isSearchLoupeHidden: Bool {
        get { searchLoupe.isHidden }
        set { setVisibility(searchLoupe, hidden: newValue) }
    }

    var isDismissButtonHidden: Bool {
        get { dismissButton.isHidden }
        set { setVisibility(dismissButton, hidden: newValue) }
    }

    /*
     Superfluous check to overcome apple bug in stack view where setting value more than
     once causes issues, related to http://www.openradar.me/22819594
     Kill this method when radar is fixed - burn it with fire ;-)
     */
    private func setVisibility(_ view: UIView, hidden: Bool) {
        if view.isHidden != hidden {
            view.isHidden = hidden
        }
    }
}
