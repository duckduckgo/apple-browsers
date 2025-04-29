//
//  UpdatedOmniBarView.swift
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
import DesignResourcesKit
import SwiftUI

final class UpdatedOmniBarView: UIView, OmniBarView {

    var textField: TextFieldWithInsets! { searchAreaView.textField }
    var privacyInfoContainer: PrivacyInfoContainerView! { searchAreaView.privacyInfoContainer }
    var notificationContainer: OmniBarNotificationContainerView! { searchAreaView.notificationContainer }
    var searchLoupe: UIView! { searchAreaView.loupeIconView }
    var dismissButton: UIButton! { searchAreaView.dismissButtonView }
    var leftIconContainerView: UIView! { searchAreaView.leftIconContainer }
    var customIconView: UIImageView { searchAreaView.customIconView }
    var clearButton: UIButton! { searchAreaView.clearButton }
    var backButton: UIButton! { backButtonView }
    var forwardButton: UIButton! { forwardButtonView }
    var settingsButton: UIButton! { settingsButtonView }
    var cancelButton: UIButton! { searchAreaView.cancelButton }
    var bookmarksButton: UIButton! { bookmarksButtonView }
    var accessoryButton: UIButton! { searchAreaView.accessoryButton }
    var menuButton: UIButton! { menuButtonView }
    var refreshButton: UIButton! { searchAreaView.reloadButton }
    var privacyIconView: UIView? { privacyInfoContainer.privacyIcon }
    var searchContainer: UIView! { searchAreaContainerView }
    let expectedHeight: CGFloat = Metrics.height

    var accessoryType: OmniBarAccessoryType = .share {
        didSet {
            switch accessoryType {
            case .chat:
                searchAreaView.accessoryButton.setImage(UIImage(resource: .aiChatNew24), for: .normal)
            case .share:
                searchAreaView.accessoryButton.setImage(UIImage(resource: .shareAppleNew24), for: .normal)
            }
            updateAccessoryAccessibility()
        }
    }

    private var searchAreaTopPaddingConstraint: NSLayoutConstraint?
    private var searchAreaBottomPaddingConstraint: NSLayoutConstraint?
    private var readableSearchAreaWidthConstraint: NSLayoutConstraint?
    private var largeSizeSpacingConstraint: NSLayoutConstraint?

    // iPad elements

    var isBackButtonHidden: Bool {
        get { backButtonView.isHidden }
        set { backButtonView.isHidden = newValue }
    }

    var isForwardButtonHidden: Bool {
        get { forwardButtonView.isHidden }
        set { forwardButtonView.isHidden = newValue }
    }

    var isBookmarksButtonHidden: Bool {
        get { bookmarksButtonView.isHidden }
        set { bookmarksButtonView.isHidden = newValue }
    }

    var isMenuButtonHidden: Bool {
        get { menuButtonView.isHidden }
        set { menuButtonView.isHidden = newValue }
    }

    var isSettingsButtonHidden: Bool {
        get { settingsButtonView.isHidden }
        set { settingsButtonView.isHidden = newValue }
    }

    // Universal elements

    var isPrivacyInfoContainerHidden: Bool {
        get { privacyInfoContainer.isHidden }
        set { privacyInfoContainer.isHidden = newValue }
    }

    var isClearButtonHidden: Bool {
        get { searchAreaView.clearButton.isHidden }
        set { searchAreaView.clearButton.isHidden = newValue }
    }

    var isCancelButtonHidden: Bool {
        get { searchAreaView.cancelButton.isHidden }
        set { searchAreaView.cancelButton.isHidden = newValue }
    }
    var isRefreshButtonHidden: Bool {
        get { searchAreaView.reloadButton.isHidden }
        set { searchAreaView.reloadButton.isHidden = newValue }
    }
    var isVoiceSearchButtonHidden: Bool {
        get { searchAreaView.voiceSearchButton.isHidden }
        set {
            searchAreaView.voiceSearchButton.isHidden = newValue
            // We want the clear button closer to the microphone if they're both visible
            // https://app.asana.com/1/137249556945/project/1206226850447395/task/1209950595275304
            searchAreaView.reduceClearButtonSpacing(!newValue)
        }
    }
    var isAbortButtonHidden: Bool {
        get { searchAreaView.cancelButton.isHidden }
        set { searchAreaView.cancelButton.isHidden = newValue }
    }

    var isAccessoryButtonHidden: Bool {
        get { searchAreaView.accessoryButton.isHidden }
        set { searchAreaView.accessoryButton.isHidden = newValue }
    }

    var isSearchLoupeHidden: Bool {
        get { searchLoupe.isHidden }
        set { searchLoupe.isHidden = newValue }
    }

    var isDismissButtonHidden: Bool {
        get { searchAreaView.dismissButtonView.isHidden }
        set { searchAreaView.dismissButtonView.isHidden = newValue }
    }

    var isUsingCompactLayout: Bool = false {
        didSet {
            leadingButtonsContainer.isHidden = isUsingCompactLayout
            trailingButtonsContainer.isHidden = isUsingCompactLayout
            leadingSpacer.isHidden = isUsingCompactLayout
            trailingSpacer.isHidden = isUsingCompactLayout
            bookmarksButtonView.isHidden = isUsingCompactLayout

            readableSearchAreaWidthConstraint?.isActive = !isUsingCompactLayout
            largeSizeSpacingConstraint?.isActive = !isUsingCompactLayout

            stackView.spacing = isUsingCompactLayout ? 0 : Metrics.expandedSizeSpacing
        }
    }

    var isShowingSeparator: Bool = false {
        didSet {
            searchAreaView.separatorView.isHidden = !isShowingSeparator
        }
    }

    var isActiveState: Bool = false {
        didSet {
            updateActiveState()
        }
    }

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

    // MARK: - Properties

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

    let settingsButtonView = ToolbarButton()
    let bookmarksButtonView = ToolbarButton()
    let menuButtonView = ToolbarButton()
    let forwardButtonView = ToolbarButton()
    let backButtonView = ToolbarButton()

    var menuButtonContent: MenuButton = MenuButton()

    var searchContainerWidth: CGFloat { searchAreaView.frame.width }

    private let omniBarProgressView = OmniBarProgressView()
    var progressView: ProgressView? { omniBarProgressView.progressView }

    private let leadingButtonsContainer = UIStackView()
    private let trailingButtonsContainer = UIStackView()

    private let searchAreaView = UpdatedOmniBarSearchView()
    private let searchAreaContainerView = CompositeShadowView()
    private let searchAreaStackView = UIStackView()
    private let activeOutlineView = UIView()

    private let leadingSpacer = UIView()
    private let trailingSpacer = UIView()

    private let stackView = UIStackView()

    static func create() -> Self {
        Self.init()
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 300, height: 68))

        setUpSubviews()
        setUpConstraints()
        setUpProperties()
        setUpCallbacks()
        setUpAccessibility()

        updateActiveState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        addSubview(stackView)

        searchAreaContainerView.addSubview(searchAreaView)
        searchAreaContainerView.addSubview(omniBarProgressView)

        searchAreaStackView.addArrangedSubview(searchAreaContainerView)
        searchAreaStackView.addArrangedSubview(bookmarksButtonView)

        stackView.addArrangedSubview(leadingButtonsContainer)
        stackView.addArrangedSubview(leadingSpacer)
        stackView.addArrangedSubview(searchAreaStackView)
        stackView.addArrangedSubview(trailingSpacer)
        stackView.addArrangedSubview(trailingButtonsContainer)

        leadingButtonsContainer.addArrangedSubview(backButtonView)
        leadingButtonsContainer.addArrangedSubview(forwardButtonView)

        trailingButtonsContainer.addArrangedSubview(menuButtonView)
        trailingButtonsContainer.addArrangedSubview(settingsButtonView)

        addSubview(activeOutlineView)
    }

    private func setUpConstraints() {

        let readableSearchAreaWidth = searchAreaContainerView.widthAnchor.constraint(equalTo: readableContentGuide.widthAnchor)
        readableSearchAreaWidth.priority = .init(999)
        readableSearchAreaWidth.isActive = false

        let searchAreaCenterXConstraint = searchAreaContainerView.centerXAnchor.constraint(equalTo: centerXAnchor)
        searchAreaCenterXConstraint.priority = .defaultHigh

        let searchAreaTopPadding = stackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.textAreaTopPadding)
        let searchAreaBottomPadding = stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.textAreaBottomPadding)

        let largeSizeSpacing = leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor)
        largeSizeSpacing.priority = .init(700)
        largeSizeSpacing.isActive = false

        searchAreaTopPaddingConstraint = searchAreaTopPadding
        searchAreaBottomPaddingConstraint = searchAreaBottomPadding
        readableSearchAreaWidthConstraint = readableSearchAreaWidth
        largeSizeSpacingConstraint = largeSizeSpacing

        omniBarProgressView.translatesAutoresizingMaskIntoConstraints = false
        activeOutlineView.translatesAutoresizingMaskIntoConstraints = false
        searchAreaView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Metrics.textAreaHorizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Metrics.textAreaHorizontalPadding),
            searchAreaTopPadding,
            searchAreaBottomPadding,

            searchAreaView.topAnchor.constraint(greaterThanOrEqualTo: searchAreaContainerView.topAnchor),
            searchAreaView.bottomAnchor.constraint(lessThanOrEqualTo: searchAreaContainerView.bottomAnchor),
            searchAreaView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
            searchAreaView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),
            searchAreaView.centerYAnchor.constraint(equalTo: searchAreaContainerView.centerYAnchor),

            searchAreaCenterXConstraint,
            readableSearchAreaWidth,

            activeOutlineView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor, constant: -Metrics.activeBorderWidth/2),
            activeOutlineView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor, constant: Metrics.activeBorderWidth/2),
            activeOutlineView.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor, constant: -Metrics.activeBorderWidth/2),
            activeOutlineView.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor, constant: Metrics.activeBorderWidth/2),

            omniBarProgressView.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor),
            omniBarProgressView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
            omniBarProgressView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),
            omniBarProgressView.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor)
        ])

        UpdatedOmniBarView.activateItemSizeConstraints(for: backButtonView)
        UpdatedOmniBarView.activateItemSizeConstraints(for: forwardButtonView)
        UpdatedOmniBarView.activateItemSizeConstraints(for: bookmarksButtonView)
        UpdatedOmniBarView.activateItemSizeConstraints(for: menuButtonView)
        UpdatedOmniBarView.activateItemSizeConstraints(for: settingsButtonView)
    }

    private func setUpProperties() {

        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        backgroundColor = UIColor(designSystemColor: .background)

        searchAreaContainerView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        searchAreaContainerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchAreaContainerView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        searchAreaContainerView.setContentHuggingPriority(.defaultLow, for: .vertical)

        searchAreaContainerView.backgroundColor = UIColor(designSystemColor: .urlBar)
        searchAreaContainerView.layer.cornerRadius = Metrics.cornerRadius

        searchAreaView.layer.cornerRadius = Metrics.cornerRadius

        activeOutlineView.isUserInteractionEnabled = false
        activeOutlineView.translatesAutoresizingMaskIntoConstraints = false
        activeOutlineView.layer.borderColor = UIColor(Color(designSystemColor: .accent)).cgColor
        activeOutlineView.layer.borderWidth = Metrics.activeBorderWidth
        activeOutlineView.backgroundColor = .clear

        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fill

        searchAreaStackView.spacing = Metrics.expandedSizeSpacing

        trailingButtonsContainer.isHidden = true

        leadingButtonsContainer.isHidden = true

        backButtonView.setImage(UIImage(resource: .arrowLeftSmall24))
        UpdatedOmniBarView.setUpCommonProperties(for: backButtonView)

        forwardButtonView.setImage(UIImage(resource: .arrowRightNew24))
        UpdatedOmniBarView.setUpCommonProperties(for: forwardButtonView)

        bookmarksButtonView.setImage(UIImage(resource: .bookmarksStacked24))
        UpdatedOmniBarView.setUpCommonProperties(for: bookmarksButtonView)

        menuButtonView.setImage(UIImage(resource: .menuHamburgerNew24))
        UpdatedOmniBarView.setUpCommonProperties(for: menuButtonView)

        settingsButtonView.setImage(UIImage(resource: .settingsNew24))
        UpdatedOmniBarView.setUpCommonProperties(for: settingsButtonView)

        progressView?.hide()

        updateShadows()
    }

    private func setUpCallbacks() {
        searchAreaView.dismissButtonView.addTarget(self, action: #selector(dismissButtonTap), for: .touchUpInside)
        searchAreaView.voiceSearchButton.addTarget(self, action: #selector(voiceSearchButtonTap), for: .touchUpInside)
        searchAreaView.reloadButton.addTarget(self, action: #selector(reloadButtonTap), for: .touchUpInside)
        searchAreaView.clearButton.addTarget(self, action: #selector(clearButtonTap), for: .touchUpInside)
        searchAreaView.cancelButton.addTarget(self, action: #selector(cancelButtonTap), for: .touchUpInside)
        searchAreaView.accessoryButton.addTarget(self, action: #selector(accessoryButtonTap), for: .touchUpInside)

        forwardButtonView.addTarget(self, action: #selector(forwardButtonTap), for: .touchUpInside)
        backButtonView.addTarget(self, action: #selector(backButtonTap), for: .touchUpInside)
        settingsButtonView.addTarget(self, action: #selector(settingsButtonTap), for: .touchUpInside)
        bookmarksButtonView.addTarget(self, action: #selector(bookmarksButtonTap), for: .touchUpInside)
        menuButtonView.addTarget(self, action: #selector(menuButtonTap), for: .touchUpInside)

        searchAreaView.textField.addTarget(self, action: #selector(textFieldTextEntered), for: .primaryActionTriggered)

        privacyInfoContainer.privacyIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(privacyIconPressed)))
        searchAreaView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(searchAreaPressed)))
    }

    private func updateShadows() {
        let color = UIColor(designSystemColor: .shadowPrimary)

        let shadow1 = CompositeShadowView.Shadow(id: "shadow1", color: color, opacity: 1, radius: 6.0, offset: CGSize(width: 0, height: 2))
        // These two have the same name so we can update the existing shadow
        let shadow2Inactive = CompositeShadowView.Shadow(id: "shadow2", color: color, opacity: 0, radius: 24.0, offset: CGSize(width: 0, height: 16))
        let shadow2Active = CompositeShadowView.Shadow(id: "shadow2", color: color, opacity: 1, radius: 24.0, offset: CGSize(width: 0, height: 16))

        let secondaryShadow = isActiveState ? shadow2Active : shadow2Inactive

        if searchAreaContainerView.shadows.isEmpty {
            let shadows = [shadow1, secondaryShadow].compactMap { $0 }
            searchAreaContainerView.shadows = shadows
        } else {
            searchAreaContainerView.updateShadow(secondaryShadow)
        }
    }

    private func setUpAccessibility() {

        backButtonView.accessibilityLabel = "Browse back"
        backButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.BrowseBack"
        backButtonView.accessibilityTraits = .button
        
        forwardButtonView.accessibilityLabel = "Browse forward"
        forwardButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.BrowseForward"
        forwardButtonView.accessibilityTraits = .button

        bookmarksButtonView.accessibilityLabel = "Bookmarks"
        bookmarksButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.Bookmarks"
        bookmarksButtonView.accessibilityTraits = .button

        menuButtonView.accessibilityLabel = "Browsing Menu"
        menuButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.BrowsingMenu"
        menuButtonView.accessibilityTraits = .button

        settingsButtonView.accessibilityLabel = "Settings"
        settingsButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.Settings"
        settingsButtonView.accessibilityTraits = .button

        accessoryButton.accessibilityLabel = "AI Chat"
        accessoryButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.AI Chat"
        accessoryButton.accessibilityTraits = .button

        // This is for compatibility purposes with old OmniBar
        searchAreaView.accessibilityIdentifier = "searchEntry"
        searchAreaView.accessibilityTraits = .searchField

        privacyIconView?.accessibilityIdentifier = "PrivacyIcon"
        privacyIconView?.accessibilityTraits = .button

        searchAreaView.voiceSearchButton.accessibilityLabel = "Voice Search"
        searchAreaView.voiceSearchButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.VoiceSearch"
        searchAreaView.voiceSearchButton.accessibilityTraits = .button

        searchAreaView.reloadButton.accessibilityLabel = "Refresh page"
        searchAreaView.reloadButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.Refresh"
        searchAreaView.reloadButton.accessibilityTraits = .button

        searchAreaView.clearButton.accessibilityLabel = "Clear text"
        searchAreaView.clearButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.ClearText"
        searchAreaView.clearButton.accessibilityTraits = .button

        searchAreaView.cancelButton.accessibilityLabel = "Stop Loading"
        searchAreaView.cancelButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.StopLoading"
        searchAreaView.cancelButton.accessibilityTraits = .button

        searchAreaView.dismissButtonView.accessibilityLabel = "Cancel"
        searchAreaView.dismissButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.Dismiss"
        searchAreaView.dismissButtonView.accessibilityTraits = .button
    }

    private func updateAccessoryAccessibility() {
        switch accessoryType {
        case .chat:
            accessoryButton.accessibilityLabel = "AI Chat"
            accessoryButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.AIChat"
        case .share:
            accessoryButton.accessibilityLabel = "Share"
            accessoryButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.Share"
        }
        accessoryButton.accessibilityTraits = .button
    }

    private func updateActiveState() {
        searchAreaTopPaddingConstraint?.constant = isActiveState ? Metrics.activeTextAreaTopPadding : Metrics.textAreaTopPadding
        searchAreaBottomPaddingConstraint?.constant = isActiveState ? -Metrics.activeTextAreaBottomPadding : -Metrics.textAreaBottomPadding

        let cornerRadius = isActiveState ? Metrics.activeCornerRadius : Metrics.cornerRadius

        // This is needed so progress bar is clipped properly
        omniBarProgressView.layer.cornerRadius = cornerRadius
        searchAreaContainerView.layer.cornerRadius = cornerRadius
        activeOutlineView.layer.cornerRadius = cornerRadius

        activeOutlineView.alpha = isActiveState ? 1 : 0

        updateShadows()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            activeOutlineView.layer.borderColor = UIColor(Color(designSystemColor: .accent)).cgColor

            updateShadows()
        }
    }

    @objc private func privacyIconPressed() {
        onPrivacyIconPressed?()
    }

    @objc private func textFieldTextEntered() {
        onTextEntered?()
    }

    @objc private func forwardButtonTap() {
        onForwardPressed?()
    }

    @objc private func backButtonTap() {
        onBackPressed?()
    }

    @objc private func settingsButtonTap() {
        onSettingsButtonPressed?()
    }

    @objc private func bookmarksButtonTap() {
        onBookmarksPressed?()
    }

    @objc private func menuButtonTap() {
        onMenuButtonPressed?()
    }

    @objc private func dismissButtonTap() {
        onDismissPressed?()
    }

    @objc private func voiceSearchButtonTap() {
        onVoiceSearchButtonPressed?()
    }

    @objc private func reloadButtonTap() {
        onRefreshPressed?()
    }

    @objc private func clearButtonTap() {
        onClearButtonPressed?()
    }

    @objc private func cancelButtonTap() {
        onAbortButtonPressed?()
    }

    @objc private func accessoryButtonTap() {
        onAccessoryPressed?()
    }

    @objc private func searchAreaPressed() {
        onTrackersViewPressed?()
    }

    private struct Metrics {
        static let itemSize: CGFloat = 44
        static let height: CGFloat = 68

        static let cornerRadius: CGFloat = 16
        static let activeCornerRadius: CGFloat = 18

        static let activeBorderWidth: CGFloat = 2

        static let textAreaHorizontalPadding: CGFloat = 16

        static let textAreaTopPadding: CGFloat = 12
        static let textAreaBottomPadding: CGFloat = 12
        static let activeTextAreaTopPadding: CGFloat = 10
        static let activeTextAreaBottomPadding: CGFloat = 10

        static let expandedSizeSpacing: CGFloat = 24.0
        static let expandedSizeMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: expandedSizeSpacing,
            bottom: 0,
            trailing: expandedSizeSpacing
        )
    }

    private struct Constant {
        static let accessibilityPrefix = "Browser.OmniBar"
    }
}

extension UpdatedOmniBarView {
    static func activateItemSizeConstraints(for item: UIView) {
        item.widthAnchor.constraint(equalTo: item.heightAnchor).isActive = true
        item.widthAnchor.constraint(equalToConstant: Metrics.itemSize).isActive = true
    }

    static func setUpCommonProperties(for button: UIButton) {
        button.isHidden = true
    }
}

extension UpdatedOmniBarView {
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
}
