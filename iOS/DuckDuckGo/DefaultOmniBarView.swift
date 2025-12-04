//
//  DefaultOmniBarView.swift
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

public enum OmniBarIcon {
    case duckPlayer
    case specialError

    var image: UIImage {
        switch self {
        case .duckPlayer:
            return UIImage(resource: .duckPlayerURLIcon)
        case .specialError:
            return DesignSystemImages.Glyphs.Size24.globe
        }
    }
}

final class DefaultOmniBarView: UIView, OmniBarView {

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
    var aiChatButton: UIButton! { searchAreaView.aiChatButton }
    var menuButton: UIButton! { menuButtonView }
    var refreshButton: UIButton! { searchAreaView.reloadButton }
    var customizableButton: UIButton! { searchAreaView.customizableButton }
    var privacyIconView: UIView? { privacyInfoContainer.privacyIcon }
    var searchContainer: UIView! { searchAreaContainerView }
    let expectedHeight: CGFloat = DefaultOmniBarView.expectedHeight
    static let expectedHeight: CGFloat = Metrics.height

    private var readableSearchAreaWidthConstraint: NSLayoutConstraint?
    private var largeSizeSpacingConstraint: NSLayoutConstraint?
    private var textAreaTopPaddingConstraint: NSLayoutConstraint?
    private var textAreaBottomPaddingConstraint: NSLayoutConstraint?

    let fieldContainerLayoutGuide = UILayoutGuide()

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

    var isCustomizableButtonHidden: Bool {
        get { searchAreaView.customizableButton.isHidden }
        set { searchAreaView.customizableButton.isHidden = newValue }
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

    var isAIChatButtonHidden: Bool {
        get { searchAreaView.aiChatButton.isHidden }
        set { searchAreaView.aiChatButton.isHidden = newValue }
    }

    var isSearchLoupeHidden: Bool {
        get { searchLoupe.isHidden }
        set { searchLoupe.isHidden = newValue }
    }

    var isDismissButtonHidden: Bool {
        get { searchAreaView.dismissButtonView.isHidden }
        set { searchAreaView.dismissButtonView.isHidden = newValue }
    }

    /// Controls whether the AI Chat mode UI is hidden (false = AI Chat mode, true = regular mode)
    var isFullAIChatHidden: Bool = true {
        didSet {
            if isFullAIChatHidden {
                hideAIChatOmnibar()
            } else {
                showAIChatOmnibar()
            }
        }
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
    var onMenuButtonLongPressed: (() -> Void)?
    var onTrackersViewPressed: (() -> Void)?
    var onSettingsButtonPressed: (() -> Void)?
    var onCancelPressed: (() -> Void)?
    var onRefreshPressed: (() -> Void)?
    var onCustomizableButtonPressed: (() -> Void)?
    var onBackPressed: (() -> Void)?
    var onForwardPressed: (() -> Void)?
    var onBookmarksPressed: (() -> Void)?
    var onAIChatPressed: (() -> Void)?
    var onDismissPressed: (() -> Void)?
    
    /// Callback fired when the AI Chat left button is tapped
    var onAIChatLeftButtonPressed: (() -> Void)?

    /// Callback fired when the AI Chat right button is tapped
    var onAIChatRightButtonPressed: (() -> Void)?

    /// Callback fired when the omnibar branding area is tapped while in AI Chat mode
    var onAIChatBrandingPressed: (() -> Void)?

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

    private let aiChatLeftButton = BrowserChromeButton()
    private let aiChatRightButton = BrowserChromeButton()
    private var aiChatBrandingView: AIChatFullModeOmniBrandingView?

    private var aiChatLeadingSpacingConstraint: NSLayoutConstraint?
    private var aiChatTrailingSpacingConstraint: NSLayoutConstraint?

    var searchContainerWidth: CGFloat { searchAreaView.frame.width }

    private var masksTop: Bool = true
    private var clipsContent: Bool = true
    private let omniBarProgressView = OmniBarProgressView()
    var progressView: ProgressView? { omniBarProgressView.progressView }

    private let leadingButtonsContainer = UIStackView()
    private let trailingButtonsContainer = UIStackView()

    private let searchAreaView = DefaultOmniBarSearchView()
    private let searchAreaContainerView = CompositeShadowView.defaultShadowView()

    /// Spans to available width of the omni bar and allows the input field to center horizontally
    private let searchAreaAlignmentView = UIView()
    private let searchAreaStackView = UIStackView()

    /// Currently unused - should be removed if unlikely to return
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

        setUpInitialState()
        updateActiveState()
        updateVerticalSpacing()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        addSubview(aiChatLeftButton)
        addSubview(aiChatRightButton)

        addSubview(activeOutlineView)
        addLayoutGuide(fieldContainerLayoutGuide)
        
        addAIChatFullModeBrandingView()
    }
    
    private func addAIChatFullModeBrandingView() {
        let brandingView = AIChatFullModeOmniBrandingView()
        brandingView.translatesAutoresizingMaskIntoConstraints = false
        searchAreaContainerView.addSubview(brandingView)

        aiChatBrandingView = brandingView

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(aiChatBrandingViewTapped))
        brandingView.addGestureRecognizer(tapGesture)

        brandingView.isHidden = true
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

            fieldContainerLayoutGuide.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
            fieldContainerLayoutGuide.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),
            fieldContainerLayoutGuide.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor),
            fieldContainerLayoutGuide.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor)
        ])

        DefaultOmniBarView.activateItemSizeConstraints(for: backButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: forwardButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: bookmarksButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: menuButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: settingsButtonView)

        // AI Chat Full Mode
        aiChatLeftButton.translatesAutoresizingMaskIntoConstraints = false
        aiChatRightButton.translatesAutoresizingMaskIntoConstraints = false

        let aiChatButtonConstraints = [
            aiChatLeftButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Metrics.textAreaHorizontalPadding),
            aiChatLeftButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            aiChatRightButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Metrics.textAreaHorizontalPadding),
            aiChatRightButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        NSLayoutConstraint.activate(aiChatButtonConstraints)
        
        DefaultOmniBarView.activateItemSizeConstraints(for: aiChatLeftButton)
        DefaultOmniBarView.activateItemSizeConstraints(for: aiChatRightButton)

        aiChatLeadingSpacingConstraint = searchAreaContainerView.leadingAnchor.constraint(equalTo: aiChatLeftButton.trailingAnchor, constant: Metrics.buttonToSearchContainerSpace)
        aiChatTrailingSpacingConstraint = searchAreaContainerView.trailingAnchor.constraint(equalTo: aiChatRightButton.leadingAnchor, constant: -Metrics.buttonToSearchContainerSpace)

        if let brandingView = aiChatBrandingView {
            NSLayoutConstraint.activate([
                brandingView.centerXAnchor.constraint(equalTo: searchAreaContainerView.centerXAnchor),
                brandingView.centerYAnchor.constraint(equalTo: searchAreaContainerView.centerYAnchor),
                brandingView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: Metrics.textAreaHorizontalPadding),
                brandingView.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -Metrics.textAreaHorizontalPadding)
            ])
        }
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
        DefaultOmniBarView.setUpCommonProperties(for: backButtonView)

        forwardButtonView.setImage(DesignSystemImages.Glyphs.Size24.arrowRight)
        DefaultOmniBarView.setUpCommonProperties(for: forwardButtonView)

        bookmarksButtonView.setImage(DesignSystemImages.Glyphs.Size24.bookmarks)
        DefaultOmniBarView.setUpCommonProperties(for: bookmarksButtonView)

        menuButtonView.setImage(DesignSystemImages.Glyphs.Size24.menuHamburger)
        DefaultOmniBarView.setUpCommonProperties(for: menuButtonView)

        settingsButtonView.setImage(DesignSystemImages.Glyphs.Size24.settings)
        DefaultOmniBarView.setUpCommonProperties(for: settingsButtonView)
        
        refreshButton.setImage(DesignSystemImages.Glyphs.Size24.reloadSmall, for: .normal)

        aiChatLeftButton.setImage(DesignSystemImages.Glyphs.Size24.aiChatHistory, for: .normal)
        aiChatLeftButton.isHidden = true
        DefaultOmniBarView.setUpCommonProperties(for: aiChatLeftButton)

        aiChatRightButton.setImage(DesignSystemImages.Glyphs.Size24.add, for: .normal)
        aiChatRightButton.isHidden = true
        DefaultOmniBarView.setUpCommonProperties(for: aiChatRightButton)

        progressView?.hide()

        updateShadows()
    }

    private func setUpCallbacks() {
        searchAreaView.dismissButtonView.addTarget(self, action: #selector(dismissButtonTap), for: .touchUpInside)
        searchAreaView.voiceSearchButton.addTarget(self, action: #selector(voiceSearchButtonTap), for: .touchUpInside)
        searchAreaView.reloadButton.addTarget(self, action: #selector(reloadButtonTap), for: .touchUpInside)
        searchAreaView.clearButton.addTarget(self, action: #selector(clearButtonTap), for: .touchUpInside)
        searchAreaView.customizableButton.addTarget(self, action: #selector(customizableButtonTap), for: .touchUpInside)
        searchAreaView.cancelButton.addTarget(self, action: #selector(cancelButtonTap), for: .touchUpInside)
        searchAreaView.aiChatButton.addTarget(self, action: #selector(aiChatButtonTap), for: .touchUpInside)

        forwardButtonView.addTarget(self, action: #selector(forwardButtonTap), for: .touchUpInside)
        backButtonView.addTarget(self, action: #selector(backButtonTap), for: .touchUpInside)
        settingsButtonView.addTarget(self, action: #selector(settingsButtonTap), for: .touchUpInside)
        bookmarksButtonView.addTarget(self, action: #selector(bookmarksButtonTap), for: .touchUpInside)
        menuButtonView.addTarget(self, action: #selector(menuButtonTap), for: .touchUpInside)

        searchAreaView.textField.addTarget(self, action: #selector(textFieldTextEntered), for: .primaryActionTriggered)

        privacyInfoContainer.privacyIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(privacyIconPressed)))
        searchAreaView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(searchAreaPressed)))

        menuButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(menuButtonLongPress)))

        aiChatLeftButton.addTarget(self, action: #selector(aiChatLeftButtonTap), for: .touchUpInside)
        aiChatRightButton.addTarget(self, action: #selector(aiChatRightButtonTap), for: .touchUpInside)
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

        aiChatButton.accessibilityLabel = UserText.duckAiFeatureName
        aiChatButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.AIChat"
        aiChatButton.accessibilityTraits = .button

        // This is for compatibility purposes with old OmniBar
        searchAreaView.textField.accessibilityIdentifier = "searchEntry"
        searchAreaView.textField.accessibilityTraits = .searchField

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

    private func setUpInitialState() {
        // This active outline view needs to be removed in the future.  There is
        //  some indecision about whether want it or not just now when comparing with
        //  macOS, the arguments being we should have parity vs it's not need.  So leaving
        //  it in disabled for now.
        activeOutlineView.layer.cornerRadius = Metrics.cornerRadius
        activeOutlineView.alpha = 0
    }

    private func updateActiveState() {
        // This is needed so progress bar is clipped properly
        omniBarProgressView.layer.cornerRadius = Metrics.cornerRadius
        searchAreaContainerView.layer.cornerRadius = Metrics.cornerRadius
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

    @objc private func menuButtonLongPress() {
        onMenuButtonLongPressed?()
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

    @objc private func customizableButtonTap() {
        onCustomizableButtonPressed?()
    }

    @objc private func cancelButtonTap() {
        onAbortButtonPressed?()
    }

    @objc private func aiChatButtonTap() {
        onAIChatPressed?()
    }

    @objc private func searchAreaPressed() {
        onTrackersViewPressed?()
    }

    @objc private func aiChatLeftButtonTap() {
        onAIChatLeftButtonPressed?()
    }

    @objc private func aiChatRightButtonTap() {
        onAIChatRightButtonPressed?()
    }

    @objc private func aiChatBrandingViewTapped() {
        onAIChatBrandingPressed?()
    }

    private struct Metrics {
        static let itemSize: CGFloat = 44
        static let height: CGFloat = 60

        static let cornerRadius: CGFloat = 16

        static let activeBorderRadius: CGFloat = 18
        static let activeBorderWidth: CGFloat = 2

        static let textAreaHorizontalPadding: CGFloat = 16
        
        static let buttonToSearchContainerSpace: CGFloat = 4

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

extension DefaultOmniBarView {
    static func activateItemSizeConstraints(for item: UIView) {
        item.widthAnchor.constraint(equalTo: item.heightAnchor).isActive = true
        item.widthAnchor.constraint(equalToConstant: Metrics.itemSize).isActive = true
    }

    static func setUpCommonProperties(for button: UIButton) {
        button.isHidden = true
    }
}

extension DefaultOmniBarView {
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

    func hideButtons() {
        privacyInfoContainer.alpha = 0
        searchAreaView.hideButtons()
    }

    func revealButtons() {
        privacyInfoContainer.alpha = 1
        searchAreaView.revealButtons()
    }

    /// Configures the omnibar UI for AI Chat mode. Shows AI Chat buttons, hides search elements.
    private func showAIChatOmnibar() {
        aiChatBrandingView?.isHidden = false
        searchAreaView.textField.isHidden = true

        aiChatLeadingSpacingConstraint?.isActive = true
        aiChatTrailingSpacingConstraint?.isActive = true
        aiChatLeftButton.isHidden = false
        aiChatRightButton.isHidden = false
        aiChatLeftButton.alpha = 1.0
        aiChatRightButton.alpha = 1.0

        layoutIfNeeded()
    }

    /// Restores the omnibar UI to regular browse mode. Hides AI Chat buttons, shows search elements.
    private func hideAIChatOmnibar() {
        aiChatBrandingView?.isHidden = true
        searchAreaView.textField.isHidden = false
        aiChatLeadingSpacingConstraint?.isActive = false
        aiChatTrailingSpacingConstraint?.isActive = false
        aiChatLeftButton.isHidden = true
        aiChatRightButton.isHidden = true
        aiChatLeftButton.alpha = 0.0
        aiChatRightButton.alpha = 0.0

        searchAreaView.textField.alpha = 1.0
        searchAreaView.revealButtons()

        layoutIfNeeded()
    }

    // Used to mask shadows going outside of bounds to prevent them covering other content
    func updateMaskLayer(maskTop: Bool, clip: Bool) {
        self.masksTop = maskTop
        self.clipsContent = clip
        updateMaskLayer()
    }

    private func updateMaskLayer() {
        guard clipsContent else {
            layer.mask = nil
            return
        }

        let maskLayer = CALayer()

        let clippingOffset = 100.0
        let inset = clippingOffset * 2

        // Make the frame uniformly larger along each axis and offset to top or bottom
        let maskFrame = layer.bounds
            .insetBy(dx: -inset, dy: -inset)
            .offsetBy(dx: 0, dy: masksTop ? inset : -inset)

        maskLayer.frame = maskFrame
        maskLayer.backgroundColor = UIColor.black.cgColor

        layer.mask = maskLayer
    }
}
