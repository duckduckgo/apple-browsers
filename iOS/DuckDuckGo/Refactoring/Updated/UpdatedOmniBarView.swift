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
import DesignResourcesKitIcons
import SwiftUI
import UIComponents

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
    var shareButton: UIButton! { searchAreaView.shareButton }
    var privacyIconView: UIView? { privacyInfoContainer.privacyIcon }
    var searchContainer: UIView! { searchAreaContainerView }
    let expectedHeight: CGFloat = UpdatedOmniBarView.expectedHeight
    static let expectedHeight: CGFloat = Metrics.height

    var accessoryType: OmniBarAccessoryType = .chat {
        didSet {
            switch accessoryType {
            case .chat:
                searchAreaView.accessoryButton.setImage(DesignSystemImages.Glyphs.Size24.aiChat, for: .normal)
                searchAreaView.accessoryButton.accessibilityLabel = UserText.aiChatFeatureName
            }
            updateAccessoryAccessibility()
        }
    }

    private var readableSearchAreaWidthConstraint: NSLayoutConstraint?
    private var largeSizeSpacingConstraint: NSLayoutConstraint?
    private var textAreaTopPaddingConstraint: NSLayoutConstraint?
    private var textAreaBottomPaddingConstraint: NSLayoutConstraint?

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

    var isShareButtonHidden: Bool {
        get { searchAreaView.shareButton.isHidden }
        set { searchAreaView.shareButton.isHidden = newValue }
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
            bookmarksButtonView.isHidden = isUsingCompactLayout

            readableSearchAreaWidthConstraint?.isActive = !isUsingCompactLayout
            largeSizeSpacingConstraint?.isActive = !isUsingCompactLayout
        }
    }

    var isUsingSmallTopSpacing: Bool = false {
        didSet {
            updateVerticalSpacing()
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
    var onSharePressed: (() -> Void)?
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

    let settingsButtonView = BrowserChromeButton()
    let bookmarksButtonView = BrowserChromeButton()
    let menuButtonView = BrowserChromeButton()
    let forwardButtonView = BrowserChromeButton()
    let backButtonView = BrowserChromeButton()

    var menuButtonContent: MenuButton = MenuButton()

    var searchContainerWidth: CGFloat { searchAreaView.frame.width }

    private var masksTop: Bool = true
    private let omniBarProgressView = OmniBarProgressView()
    var progressView: ProgressView? { omniBarProgressView.progressView }

    private let leadingButtonsContainer = UIStackView()
    private let trailingButtonsContainer = UIStackView()

    private let searchAreaView = UpdatedOmniBarSearchView()
    private let searchAreaContainerView = CompositeShadowView.defaultShadowView()

    /// Spans to available width of the omni bar and allows the input field to center horizontally
    private let searchAreaAlignmentView = UIView()
    private let searchAreaStackView = UIStackView()
    private let activeOutlineView = UIView()

    private let stackView = UIStackView()

    static func create() -> Self {
        Self.init()
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 300, height: Metrics.height))

        setUpSubviews()
        setUpConstraints()
        setUpProperties()
        setUpCallbacks()
        setUpAccessibility()

        updateActiveState()
        updateVerticalSpacing()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // To be replaced with AppUserDefaults.Notifications.addressBarPositionChanged after release
        // https://app.asana.com/1/137249556945/project/1207252092703676/task/1210323588862346?focus=true
        NotificationCenter.default.post(name: DefaultOmniBarView.didLayoutNotification, object: self.frame.height)
        updateMaskLayer()
    }

    private func setUpSubviews() {
        addSubview(stackView)

        stackView.addArrangedSubview(leadingButtonsContainer)
        stackView.addArrangedSubview(searchAreaAlignmentView)
        stackView.addArrangedSubview(trailingButtonsContainer)

        leadingButtonsContainer.addArrangedSubview(backButtonView)
        leadingButtonsContainer.addArrangedSubview(forwardButtonView)

        searchAreaAlignmentView.addSubview(searchAreaStackView)

        searchAreaStackView.addArrangedSubview(searchAreaContainerView)

        searchAreaContainerView.addSubview(searchAreaView)
        searchAreaContainerView.addSubview(omniBarProgressView)

        trailingButtonsContainer.addArrangedSubview(bookmarksButtonView)
        trailingButtonsContainer.addArrangedSubview(menuButtonView)
        trailingButtonsContainer.addArrangedSubview(settingsButtonView)

        addSubview(activeOutlineView)
    }

    private func setUpConstraints() {

        let readableSearchAreaWidth = searchAreaContainerView.widthAnchor.constraint(equalTo: readableContentGuide.widthAnchor)
        readableSearchAreaWidth.priority = .init(999)
        readableSearchAreaWidth.isActive = false

        let textAreaTopPaddingConstraint = stackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.textAreaVerticalPaddingRegularSpacing)
        let textAreaBottomPaddingConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.textAreaVerticalPaddingRegularSpacing)

        readableSearchAreaWidthConstraint = readableSearchAreaWidth
        self.textAreaTopPaddingConstraint = textAreaTopPaddingConstraint
        self.textAreaBottomPaddingConstraint = textAreaBottomPaddingConstraint

        omniBarProgressView.translatesAutoresizingMaskIntoConstraints = false
        activeOutlineView.translatesAutoresizingMaskIntoConstraints = false
        searchAreaView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        searchAreaStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Metrics.textAreaHorizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Metrics.textAreaHorizontalPadding),
            textAreaTopPaddingConstraint,
            textAreaBottomPaddingConstraint,

            searchAreaView.topAnchor.constraint(greaterThanOrEqualTo: searchAreaContainerView.topAnchor),
            searchAreaView.bottomAnchor.constraint(lessThanOrEqualTo: searchAreaContainerView.bottomAnchor),
            searchAreaView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
            searchAreaView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),
            searchAreaView.centerYAnchor.constraint(equalTo: searchAreaContainerView.centerYAnchor),

            searchAreaContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            readableSearchAreaWidth,

            activeOutlineView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor, constant: -Metrics.activeBorderWidth),
            activeOutlineView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor, constant: Metrics.activeBorderWidth),
            activeOutlineView.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor, constant: -Metrics.activeBorderWidth),
            activeOutlineView.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor, constant: Metrics.activeBorderWidth),

            omniBarProgressView.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor),
            omniBarProgressView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
            omniBarProgressView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),
            omniBarProgressView.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor),

            searchAreaStackView.topAnchor.constraint(equalTo: searchAreaAlignmentView.topAnchor),
            searchAreaStackView.bottomAnchor.constraint(equalTo: searchAreaAlignmentView.bottomAnchor),
            searchAreaStackView.leadingAnchor.constraint(greaterThanOrEqualTo: searchAreaAlignmentView.leadingAnchor),
            searchAreaStackView.trailingAnchor.constraint(lessThanOrEqualTo: searchAreaAlignmentView.trailingAnchor),

            // We want searchAreaStackView to grow as much as it's possible
            searchAreaStackView.widthAnchor.constraint(equalTo: widthAnchor).withPriority(.defaultHigh),
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

        searchAreaAlignmentView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchAreaAlignmentView.setContentCompressionResistancePriority(.required, for: .horizontal)

        searchAreaContainerView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        searchAreaContainerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchAreaContainerView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        searchAreaContainerView.setContentHuggingPriority(.defaultLow, for: .vertical)

        searchAreaContainerView.backgroundColor = UIColor(designSystemColor: .urlBar)
        searchAreaContainerView.layer.cornerRadius = Metrics.cornerRadius
        searchAreaContainerView.layer.cornerCurve = .continuous

        searchAreaView.layer.cornerRadius = Metrics.cornerRadius
        searchAreaView.layer.cornerCurve = .continuous

        activeOutlineView.isUserInteractionEnabled = false
        activeOutlineView.translatesAutoresizingMaskIntoConstraints = false
        activeOutlineView.layer.borderColor = UIColor(Color(designSystemColor: .accent)).cgColor
        activeOutlineView.layer.borderWidth = Metrics.activeBorderWidth
        activeOutlineView.layer.cornerRadius = Metrics.activeBorderRadius
        activeOutlineView.layer.cornerCurve = .continuous
        activeOutlineView.backgroundColor = .clear

        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = Metrics.expandedSizeSpacing

        searchAreaStackView.spacing = Metrics.expandedSizeSpacing

        trailingButtonsContainer.isHidden = true

        leadingButtonsContainer.isHidden = true

        backButtonView.setImage(DesignSystemImages.Glyphs.Size24.arrowLeftSmall)
        UpdatedOmniBarView.setUpCommonProperties(for: backButtonView)

        forwardButtonView.setImage(DesignSystemImages.Glyphs.Size24.arrowRight)
        UpdatedOmniBarView.setUpCommonProperties(for: forwardButtonView)

        bookmarksButtonView.setImage(DesignSystemImages.Glyphs.Size24.bookmarks)
        UpdatedOmniBarView.setUpCommonProperties(for: bookmarksButtonView)

        menuButtonView.setImage(DesignSystemImages.Glyphs.Size24.menuHamburger)
        UpdatedOmniBarView.setUpCommonProperties(for: menuButtonView)

        settingsButtonView.setImage(DesignSystemImages.Glyphs.Size24.settings)
        UpdatedOmniBarView.setUpCommonProperties(for: settingsButtonView)
        
        refreshButton.setImage(DesignSystemImages.Glyphs.Size24.reloadSmall, for: .normal)

        progressView?.hide()

        updateShadows()
    }

    private func setUpCallbacks() {
        searchAreaView.dismissButtonView.addTarget(self, action: #selector(dismissButtonTap), for: .touchUpInside)
        searchAreaView.voiceSearchButton.addTarget(self, action: #selector(voiceSearchButtonTap), for: .touchUpInside)
        searchAreaView.reloadButton.addTarget(self, action: #selector(reloadButtonTap), for: .touchUpInside)
        searchAreaView.clearButton.addTarget(self, action: #selector(clearButtonTap), for: .touchUpInside)
        searchAreaView.shareButton.addTarget(self, action: #selector(shareButtonTap), for: .touchUpInside)
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
        if isActiveState {
            searchAreaContainerView.applyActiveShadow()
        } else {
            searchAreaContainerView.applyDefaultShadow()
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
        }
        accessoryButton.accessibilityTraits = .button
    }

    private func updateActiveState() {
        // This is needed so progress bar is clipped properly
        omniBarProgressView.layer.cornerRadius = Metrics.cornerRadius
        searchAreaContainerView.layer.cornerRadius = Metrics.cornerRadius
        activeOutlineView.layer.cornerRadius = isActiveState ? Metrics.activeBorderRadius : Metrics.cornerRadius

        activeOutlineView.alpha = isActiveState ? 1 : 0

        updateShadows()
    }

    private func updateVerticalSpacing() {
        textAreaTopPaddingConstraint?.constant = isUsingSmallTopSpacing ? Metrics.textAreaTopPaddingAdjustedSpacing : Metrics.textAreaVerticalPaddingRegularSpacing
        textAreaBottomPaddingConstraint?.constant = -(isUsingSmallTopSpacing ? Metrics.textAreaBottomPaddingAdjustedSpacing : Metrics.textAreaVerticalPaddingRegularSpacing)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            activeOutlineView.layer.borderColor = UIColor(Color(designSystemColor: .accent)).cgColor
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

    @objc private func shareButtonTap() {
        onSharePressed?()
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
        static let height: CGFloat = 60

        static let cornerRadius: CGFloat = 16

        static let activeBorderRadius: CGFloat = 18
        static let activeBorderWidth: CGFloat = 2

        static let textAreaHorizontalPadding: CGFloat = 16

        // Used when OmniBar is positioned on the bottom of the screen
        static let textAreaTopPaddingAdjustedSpacing: CGFloat = 10
        static let textAreaBottomPaddingAdjustedSpacing: CGFloat = 6

        static let textAreaVerticalPaddingRegularSpacing: CGFloat = 8

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

    // Used to mask shadows going outside of bounds to prevent them covering other content
    func updateMaskLayer(maskTop: Bool) {
        self.masksTop = maskTop

        updateMaskLayer()
    }

    private func updateMaskLayer() {
        let maskLayer = CALayer()

        let clippingOffset = 100.0
        let inset = clippingOffset * 2

        // Make the frame uniformly larger along each axis and offset to top or bottom
        let maskFrame = layer.bounds
            .insetBy(dx: -inset, dy: -inset)
            .offsetBy(dx: 0, dy: masksTop ? clippingOffset : -clippingOffset)

        maskLayer.frame = maskFrame
        maskLayer.backgroundColor = UIColor.black.cgColor

        layer.mask = maskLayer
    }
}
