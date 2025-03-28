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

    var accessoryType: OmniBarAccessoryType = .share {
        didSet {
            switch accessoryType {
            case .chat:
                accessoryButton.setImage(UIImage(named: "AIChat-24"), for: .normal)
            case .share:
                accessoryButton.setImage(UIImage(named: "Share-24"), for: .normal)
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
        configureTextField()
        configureSettingsLongPressButton()
        configureShareLongPressButton()

        configureSeparator()
        enableInteractionsWithPointer()
        
        privacyInfoContainer.isHidden = true

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
        
    private func enableInteractionsWithPointer() {
        backButton.isPointerInteractionEnabled = true
        forwardButton.isPointerInteractionEnabled = true
        settingsButton.isPointerInteractionEnabled = true
        cancelButton.isPointerInteractionEnabled = true
        bookmarksButton.isPointerInteractionEnabled = true
        accessoryButton.isPointerInteractionEnabled = true
        menuButton.isPointerInteractionEnabled = true

        refreshButton.isPointerInteractionEnabled = true
        refreshButton.pointerStyleProvider = { button, _, _ -> UIPointerStyle? in
            return .init(effect: .lift(.init(view: button)))
        }
    }
    
    private func configureMenuButton() {
        menuButton.addSubview(menuButtonContent)
        menuButton.isAccessibilityElement = true
        menuButton.accessibilityTraits = .button
    }
    
    private func configureTextField() {
        textField.textDragInteraction?.isEnabled = false
        
        textField.onCopyAction = { field in
            guard let range = field.selectedTextRange else { return }
            UIPasteboard.general.string = field.text(in: range)
        }
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

    func removeTextSelection() {
        textField.selectedTextRange = nil
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
        
        configureTextField()

        editingBackground?.backgroundColor = theme.searchBarBackgroundColor
        editingBackground?.borderColor = theme.searchBarBackgroundColor

        searchStackContainer?.tintColor = theme.barTintColor
        
        textField.textColor = theme.searchBarTextColor
        textField.tintColor = UIColor(designSystemColor: .accent)
        textField.keyboardAppearance = theme.keyboardAppearance
        clearButton.tintColor = UIColor(designSystemColor: .icons)
        voiceSearchButton.tintColor = UIColor(designSystemColor: .icons)
        
        searchLoupe.tintColor = UIColor(designSystemColor: .icons)
        searchLoupe.alpha = 0.5
        cancelButton.setTitleColor(theme.barTintColor, for: .normal)
    }
}

extension DefaultOmniBarView: OmniBarView {
    
    var text: String? {
        get { textField.text }
        set { textField.text = newValue }
    }
    
    var backButtonMenu: UIMenu? {
        get { backButton.menu }
        set { backButton.menu = newValue }
    }
    
    var forwardButtonMenu: UIMenu? {
        get { forwardButton.menu }
        set { forwardButton.menu = newValue }
    }
    
    var menuButtonView: UIButton {
        menuButton
    }

    var bookmarksButtonView: UIButton {
        bookmarksButton
    }
    
    var accessoryButtonView: UIButton {
        accessoryButton
    }
    
    var searchContainerWidth: CGFloat {
        searchStackContainer.frame.width
    }

    var searchContainerView: UIView {
        searchContainer
    }

    var privacyIconView: UIView? {
        privacyInfoContainer.privacyIcon
    }

    var progressView: ProgressView? {
        nil
    }
}
