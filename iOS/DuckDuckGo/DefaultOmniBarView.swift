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
    case duckAI
    case specialError

    var image: UIImage {
        switch self {
        case .duckPlayer:
            return UIImage(resource: .duckPlayerURLIcon)
        case .duckAI:
            return DesignSystemImages.Color.Size24.aiChatGradient
        case .specialError:
            return DesignSystemImages.Glyphs.Size24.globe
        }
    }
}

final class DefaultOmniBarView: UIView, OmniBarView, ExpandableOmniBarView {

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
    private var stackViewLeadingConstraint: NSLayoutConstraint?
    private var stackViewTrailingConstraint: NSLayoutConstraint?

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
        get { bookmarksButtonView.isHidden && leadingBookmarksButtonView.isHidden }
        set {
            bookmarksButtonView.isHidden = newValue
            leadingBookmarksButtonView.isHidden = newValue
        }
    }

    func setBookmarksPosition(leading: Bool, hidden: Bool) {
        leadingBookmarksButtonView.isHidden = leading ? hidden : true
        bookmarksButtonView.isHidden = leading ? true : hidden
    }

    var isPasswordsButtonHidden: Bool {
        get { passwordsButtonView.isHidden }
        set { passwordsButtonView.isHidden = newValue }
    }

    var isMenuButtonHidden: Bool {
        get { menuButtonView.isHidden }
        set { menuButtonView.isHidden = newValue }
    }

    var isSettingsButtonHidden: Bool {
        get { settingsButtonView.isHidden }
        set { settingsButtonView.isHidden = newValue }
    }

    var isFireButtonHidden: Bool {
        get { fireButtonView.isHidden }
        set { fireButtonView.isHidden = newValue }
    }

    var isTabSwitcherButtonHidden: Bool {
        get { tabSwitcherContainerView.isHidden }
        set { tabSwitcherContainerView.isHidden = newValue }
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
    
    var isExternalRefreshButtonHidden: Bool {
        get { externalRefreshButtonView.isHidden }
        set { externalRefreshButtonView.isHidden = newValue }
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
    
    var isModeToggleHidden: Bool {
        get { searchAreaView.isModeToggleHidden }
        set { searchAreaView.isModeToggleHidden = newValue }
    }
    
    var selectedModeToggleState: TextEntryMode {
        get { searchAreaView.modeToggleView.selectedMode }
        set { searchAreaView.modeToggleView.selectedMode = newValue }
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
            guard oldValue != isFullAIChatHidden else { return }
            if isFullAIChatHidden {
                hideAIChatOmnibar()
            } else {
                showAIChatOmnibar()
            }
        }
    }

    private(set) var layoutMode: OmniBarLayoutMode = .compact

    func setLayoutMode(_ newMode: OmniBarLayoutMode, animated: Bool = false) {
        guard layoutMode != newMode else { return }

        if animated {
            layoutIfNeeded()
            let entering = newMode == .compact
            if entering {
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                    self.leadingButtonsContainer.alpha = 0
                    self.trailingButtonsContainer.alpha = 0
                    self.applyLayoutMode(newMode)
                    self.layoutIfNeeded()
                }
            } else {
                leadingButtonsContainer.alpha = 0
                trailingButtonsContainer.alpha = 0
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                    self.leadingButtonsContainer.alpha = 1
                    self.trailingButtonsContainer.alpha = 1
                    self.applyLayoutMode(newMode)
                    self.layoutIfNeeded()
                }
            }
        } else {
            applyLayoutMode(newMode)
        }
    }

    private func applyLayoutMode(_ newMode: OmniBarLayoutMode) {
        layoutMode = newMode
        let showButtons = newMode != .compact
        leadingButtonsContainer.isHidden = !showButtons
        trailingButtonsContainer.isHidden = !showButtons
        readableSearchAreaWidthConstraint?.isActive = showButtons
        largeSizeSpacingConstraint?.isActive = showButtons

        let isLandscape = newMode == .phoneLandscape
        leadingButtonsContainer.spacing = isLandscape ? Metrics.phoneLandscapeButtonSpacing : 0
        trailingButtonsContainer.spacing = isLandscape ? Metrics.phoneLandscapeButtonSpacing : 0
        stackView.spacing = isLandscape ? Metrics.phoneLandscapeButtonSpacing : Metrics.expandedSizeSpacing
        stackViewLeadingConstraint?.constant = isLandscape ? Metrics.phoneLandscapeEdgePadding : Metrics.textAreaHorizontalPadding
        stackViewTrailingConstraint?.constant = isLandscape ? -Metrics.phoneLandscapeEdgePadding : -Metrics.textAreaHorizontalPadding
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

    private var fireMode: Bool = false

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
    var onPasswordsPressed: (() -> Void)?
    var onAIChatPressed: (() -> Void)?
    var onDismissPressed: (() -> Void)?
    var onFirePressed: (() -> Void)?
    var onSearchModePressed: (() -> Void)?
    var onAIChatModePressed: (() -> Void)?
    
    /// Callback fired when the AI Chat left button is tapped
    var onAIChatLeftButtonPressed: (() -> Void)?

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
    /// Needed because UIStackView doesn't support reparenting — one in leading, one in trailing.
    let leadingBookmarksButtonView = BrowserChromeButton()
    let passwordsButtonView = BrowserChromeButton()
    let menuButtonView = BrowserChromeButton()
    let forwardButtonView = BrowserChromeButton()
    let backButtonView = BrowserChromeButton()
    let externalRefreshButtonView = BrowserChromeButton()
    let fireButtonView = BrowserChromeButton()
    let tabSwitcherContainerView = UIView()

    private let aiChatLeftButton = BrowserChromeButton()
    private var aiChatBrandingView: AIChatFullModeOmniBrandingView?
    private var aiChatModeConstraints: [NSLayoutConstraint] = []

    // MARK: - iPad Duck.ai Expanded Search Area (stored properties)

    let aiChatSendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(DesignSystemImages.Glyphs.Size24.arrowRightSmall, for: .normal)
        button.isHidden = true
        button.layer.cornerRadius = Metrics.sendButtonSize / 2
        button.layer.masksToBounds = true
        return button
    }()

    var onAIChatSendPressed: (() -> Void)?
    var isAIVoiceChatEnabled: Bool = false

    let aiChatTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isHidden = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }()

    var duckAITextViewDelegate: UITextViewDelegate? {
        get { aiChatTextView.delegate }
        set { aiChatTextView.delegate = newValue }
    }
    var onSearchAreaExpandedStateChanged: ((Bool) -> Void)?
    var onCollapseAnimationCompleted: (() -> Void)?
    private(set) var isSearchAreaExpanded: Bool = false {
        didSet {
            guard oldValue != isSearchAreaExpanded, !suppressExpansionUpdate else { return }
            updateSearchAreaExpansion(animated: false)
        }
    }
    private var suppressExpansionUpdate = false
    private var searchAreaCenterYConstraint: NSLayoutConstraint?
    private var searchAreaTopPinConstraint: NSLayoutConstraint?
    private var expandedHeightConstraint: NSLayoutConstraint?
    private var searchStackBottomEqualConstraint: NSLayoutConstraint?
    private var searchStackBottomGTEConstraint: NSLayoutConstraint?

    var searchContainerWidth: CGFloat { searchAreaView.frame.width }

    private var masksTop: Bool = true
    private var clipsContent: Bool = true
    private let omniBarProgressView = OmniBarProgressView()
    var progressView: ProgressView? { omniBarProgressView.progressView }

    private(set) var leadingButtonsContainer = UIStackView()
    private(set) var trailingButtonsContainer = UIStackView()

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
        leadingButtonsContainer.addArrangedSubview(externalRefreshButtonView)
        leadingButtonsContainer.addArrangedSubview(leadingBookmarksButtonView)
        leadingButtonsContainer.addArrangedSubview(passwordsButtonView)

        searchAreaAlignmentView.addSubview(searchAreaStackView)

        searchAreaStackView.addArrangedSubview(searchAreaContainerView)

        searchAreaContainerView.addSubview(searchAreaView)
        searchAreaContainerView.addSubview(omniBarProgressView)

        trailingButtonsContainer.addArrangedSubview(fireButtonView)
        trailingButtonsContainer.addArrangedSubview(tabSwitcherContainerView)
        trailingButtonsContainer.addArrangedSubview(bookmarksButtonView)
        trailingButtonsContainer.addArrangedSubview(menuButtonView)
        trailingButtonsContainer.addArrangedSubview(settingsButtonView)

        searchAreaContainerView.addSubview(aiChatTextView)
        searchAreaContainerView.addSubview(aiChatSendButton)
        searchAreaContainerView.addSubview(aiChatLeftButton)

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

        let leadingConstraint = stackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Metrics.textAreaHorizontalPadding)
        let trailingConstraint = stackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Metrics.textAreaHorizontalPadding)
        stackViewLeadingConstraint = leadingConstraint
        stackViewTrailingConstraint = trailingConstraint

        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            textAreaTopPaddingConstraint,
            textAreaBottomPaddingConstraint,

            searchAreaView.topAnchor.constraint(greaterThanOrEqualTo: searchAreaContainerView.topAnchor),
            searchAreaView.bottomAnchor.constraint(lessThanOrEqualTo: searchAreaContainerView.bottomAnchor),
            searchAreaView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
            searchAreaView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),

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
        DefaultOmniBarView.activateItemSizeConstraints(for: externalRefreshButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: bookmarksButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: leadingBookmarksButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: passwordsButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: fireButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: menuButtonView)
        DefaultOmniBarView.activateItemSizeConstraints(for: settingsButtonView)

        // AI Chat Full Mode
        aiChatLeftButton.translatesAutoresizingMaskIntoConstraints = false

        let aiChatButtonConstraints = [
            aiChatLeftButton.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
            aiChatLeftButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        NSLayoutConstraint.activate(aiChatButtonConstraints)
        
        DefaultOmniBarView.activateItemSizeConstraints(for: aiChatLeftButton)

        // AI Chat mode constraints (inactive by default, activated only in AI Chat mode)
        if let brandingView = aiChatBrandingView {
            aiChatModeConstraints = [
                brandingView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
                brandingView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),
                brandingView.centerYAnchor.constraint(equalTo: searchAreaContainerView.centerYAnchor),
                searchAreaContainerView.widthAnchor.constraint(equalTo: searchAreaAlignmentView.widthAnchor)
            ]
        }

        setUpExpandedSearchAreaConstraints()
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
        activeOutlineView.layer.borderColor = UIColor(designSystemColor: .accent).cgColor
        activeOutlineView.layer.borderWidth = Metrics.activeBorderWidth
        activeOutlineView.layer.cornerRadius = Metrics.activeBorderRadius
        activeOutlineView.layer.cornerCurve = .continuous
        activeOutlineView.backgroundColor = .clear

        updateFireModeAppearance()

        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = Metrics.expandedSizeSpacing

        searchAreaStackView.spacing = Metrics.expandedSizeSpacing

        trailingButtonsContainer.isHidden = true

        leadingButtonsContainer.isHidden = true

        backButtonView.setImage(DesignSystemImages.Glyphs.Size24.arrowLeft)
        DefaultOmniBarView.setUpCommonProperties(for: backButtonView)

        forwardButtonView.setImage(DesignSystemImages.Glyphs.Size24.arrowRight)
        DefaultOmniBarView.setUpCommonProperties(for: forwardButtonView)
        
        externalRefreshButtonView.setImage(DesignSystemImages.Glyphs.Size24.reloadSmall)
        DefaultOmniBarView.setUpCommonProperties(for: externalRefreshButtonView)

        bookmarksButtonView.setImage(DesignSystemImages.Glyphs.Size24.bookmarks)
        DefaultOmniBarView.setUpCommonProperties(for: bookmarksButtonView)

        leadingBookmarksButtonView.setImage(DesignSystemImages.Glyphs.Size24.bookmarks)
        DefaultOmniBarView.setUpCommonProperties(for: leadingBookmarksButtonView)

        passwordsButtonView.setImage(DesignSystemImages.Glyphs.Size24.key)
        DefaultOmniBarView.setUpCommonProperties(for: passwordsButtonView)
        passwordsButtonView.isHidden = true

        menuButtonView.setImage(DesignSystemImages.Glyphs.Size24.menuHamburger)
        DefaultOmniBarView.setUpCommonProperties(for: menuButtonView)

        settingsButtonView.setImage(DesignSystemImages.Glyphs.Size24.settings)
        DefaultOmniBarView.setUpCommonProperties(for: settingsButtonView)

        fireButtonView.setImage(DesignSystemImages.Glyphs.Size24.fireSolid)
        DefaultOmniBarView.setUpCommonProperties(for: fireButtonView)
        fireButtonView.isHidden = true

        tabSwitcherContainerView.translatesAutoresizingMaskIntoConstraints = false
        tabSwitcherContainerView.isHidden = true
        DefaultOmniBarView.activateItemSizeConstraints(for: tabSwitcherContainerView)
        
        refreshButton.setImage(DesignSystemImages.Glyphs.Size24.reloadSmall, for: .normal)

        aiChatLeftButton.setImage(DesignSystemImages.Glyphs.Size24.aiChatHistory, for: .normal)
        aiChatLeftButton.isHidden = true
        DefaultOmniBarView.setUpCommonProperties(for: aiChatLeftButton)

        progressView?.hide()

        setUpExpandedTextViewProperties()

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
        leadingBookmarksButtonView.addTarget(self, action: #selector(bookmarksButtonTap), for: .touchUpInside)
        passwordsButtonView.addTarget(self, action: #selector(passwordsButtonTap), for: .touchUpInside)
        menuButtonView.addTarget(self, action: #selector(menuButtonTap), for: .touchUpInside)
        externalRefreshButtonView.addTarget(self, action: #selector(reloadButtonTap), for: .touchUpInside)
        fireButtonView.addTarget(self, action: #selector(fireButtonTap), for: .touchUpInside)
        searchAreaView.modeToggleView.onSearchTapped = { [weak self] in
            self?.onSearchModePressed?()
        }
        searchAreaView.modeToggleView.onAIChatTapped = { [weak self] in
            self?.onAIChatModePressed?()
        }

        searchAreaView.textField.addTarget(self, action: #selector(textFieldTextEntered), for: .primaryActionTriggered)

        privacyInfoContainer.privacyIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(privacyIconPressed)))
        searchAreaView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(searchAreaPressed)))

        menuButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(menuButtonLongPress)))

        aiChatLeftButton.addTarget(self, action: #selector(aiChatLeftButtonTap), for: .touchUpInside)
        aiChatSendButton.addTarget(self, action: #selector(aiChatSendButtonTap), for: .primaryActionTriggered)
    }

    private func updateFireModeAppearance() {
        if fireMode {
            searchAreaContainerView.backgroundColor = UIColor(singleUseColor: .fireModeBackground)
            activeOutlineView.layer.borderColor = UIColor(singleUseColor: .fireModeAccent).cgColor
        } else {
            searchAreaContainerView.backgroundColor = UIColor(designSystemColor: .urlBar)
            activeOutlineView.layer.borderColor = UIColor(designSystemColor: .accent).cgColor
        }
        let style: UIUserInterfaceStyle = fireMode ? .dark : .unspecified
        searchAreaContainerView.subviews.forEach { $0.overrideUserInterfaceStyle = style }
        progressView?.updateFireModeAppearance(fireMode: fireMode)
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
        
        externalRefreshButtonView.accessibilityLabel = "Refresh page"
        externalRefreshButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.RefreshExternal"
        externalRefreshButtonView.accessibilityTraits = .button

        bookmarksButtonView.accessibilityLabel = "Bookmarks"
        bookmarksButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.Bookmarks"
        bookmarksButtonView.accessibilityTraits = .button

        leadingBookmarksButtonView.accessibilityLabel = "Bookmarks"
        leadingBookmarksButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.BookmarksLeading"
        leadingBookmarksButtonView.accessibilityTraits = .button

        passwordsButtonView.accessibilityLabel = "Passwords"
        passwordsButtonView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.Passwords"
        passwordsButtonView.accessibilityTraits = .button

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

        aiChatTextView.accessibilityIdentifier = "\(Constant.accessibilityPrefix).AIChatTextView"
        aiChatTextView.accessibilityLabel = UserText.duckAiFeatureName

        aiChatSendButton.accessibilityLabel = "Send message"
        aiChatSendButton.accessibilityHint = "Sends your message to DuckDuckGo AI"
        aiChatSendButton.accessibilityIdentifier = "\(Constant.accessibilityPrefix).Button.AIChatSend"
        aiChatSendButton.accessibilityTraits = .button
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

    /// Returns the expanded-area subview (text view or send button) at the given point.
    /// When expanded, these views overflow beyond this view's bounds so we must claim them explicitly.
    private func overflowTarget(at point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isSearchAreaExpanded else { return nil }
        let candidates: [UIView] = [aiChatSendButton, aiChatTextView]
        return candidates.first { candidate in
            guard !candidate.isHidden else { return false }
            let localPoint = candidate.convert(point, from: self)
            return candidate.point(inside: localPoint, with: event)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        overflowTarget(at: point, with: event) != nil || super.point(inside: point, with: event)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let target = overflowTarget(at: point, with: event) {
            let localPoint = target.convert(point, from: self)
            return target.hitTest(localPoint, with: event) ?? target
        }
        return super.hitTest(point, with: event)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateFireModeAppearance()
        }
    }
    
    func refreshFireMode(fireMode: Bool) {
        self.fireMode = fireMode
        updateFireModeAppearance()
        setUpExpandedTextViewProperties()
        searchAreaView.updateFireModeAppearance(fireMode: fireMode)
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

    @objc private func passwordsButtonTap() {
        onPasswordsPressed?()
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
        if isSearchAreaExpanded {
            aiChatTextView.becomeFirstResponder()
            return
        }
        onTrackersViewPressed?()
    }

    @objc private func aiChatLeftButtonTap() {
        onAIChatLeftButtonPressed?()
    }

    @objc private func aiChatSendButtonTap() {
        onAIChatSendPressed?()
    }

    @objc private func aiChatBrandingViewTapped() {
        onAIChatBrandingPressed?()
    }

    @objc private func fireButtonTap() {
        onFirePressed?()
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

        static let expandedSearchAreaHeight: CGFloat = 120.0
        static let duckAITextViewBottomPadding: CGFloat = 8.0
        static let sendButtonSize: CGFloat = 40.0
        static let expansionAnimationDuration: TimeInterval = 0.25

        static let expandedSizeSpacing: CGFloat = 24.0
        static let expandedSizeMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: expandedSizeSpacing,
            bottom: 0,
            trailing: expandedSizeSpacing
        )

        static let phoneLandscapeButtonSpacing: CGFloat = 10.0
        static let phoneLandscapeEdgePadding: CGFloat = 4.0
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
        aiChatLeftButton.isHidden = false
        aiChatLeftButton.alpha = 1.0
        NSLayoutConstraint.activate(aiChatModeConstraints)
        searchAreaContainerView.bringSubviewToFront(aiChatLeftButton)

        setNeedsLayout()
    }

    /// Restores the omnibar UI to regular browse mode. Hides AI Chat buttons, shows search elements.
    private func hideAIChatOmnibar() {
        aiChatBrandingView?.isHidden = true
        aiChatLeftButton.isHidden = true
        aiChatLeftButton.alpha = 0.0
        NSLayoutConstraint.deactivate(aiChatModeConstraints)

        searchAreaView.textField.isHidden = false

        if !isSearchAreaExpanded {
            searchAreaView.textField.alpha = 1.0
            searchAreaView.revealButtons()
        }

        setNeedsLayout()
    }

    // Used to mask shadows going outside of bounds to prevent them covering other content
    func updateMaskLayer(maskTop: Bool, clip: Bool) {
        self.masksTop = maskTop
        self.clipsContent = clip
        updateMaskLayer()
    }

    private func updateMaskLayer() {
        guard clipsContent, !isSearchAreaExpanded else {
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

// MARK: - iPad Duck.ai Expanded Search Area

extension DefaultOmniBarView {

    func setSearchAreaExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isSearchAreaExpanded else { return }
        suppressExpansionUpdate = true
        isSearchAreaExpanded = expanded
        suppressExpansionUpdate = false
        updateSearchAreaExpansion(animated: animated)
    }

    func setUpExpandedSearchAreaConstraints() {
        NSLayoutConstraint.activate([
            aiChatTextView.topAnchor.constraint(equalTo: searchAreaView.textField.topAnchor),
            aiChatTextView.leadingAnchor.constraint(equalTo: searchAreaView.textField.leadingAnchor),
            aiChatTextView.trailingAnchor.constraint(equalTo: searchAreaView.textField.trailingAnchor),
            aiChatTextView.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor, constant: -Metrics.duckAITextViewBottomPadding),

            aiChatSendButton.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor, constant: -Metrics.duckAITextViewBottomPadding),
            aiChatSendButton.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor, constant: -Metrics.duckAITextViewBottomPadding),
            aiChatSendButton.widthAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
            aiChatSendButton.heightAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
        ])

        let bottomEqual = searchAreaStackView.bottomAnchor.constraint(equalTo: searchAreaAlignmentView.bottomAnchor)
        bottomEqual.isActive = true
        searchStackBottomEqualConstraint = bottomEqual

        let bottomGTE = searchAreaStackView.bottomAnchor.constraint(greaterThanOrEqualTo: searchAreaAlignmentView.bottomAnchor)
        bottomGTE.isActive = false
        searchStackBottomGTEConstraint = bottomGTE

        let centerY = searchAreaView.centerYAnchor.constraint(equalTo: searchAreaContainerView.centerYAnchor)
        centerY.isActive = true
        searchAreaCenterYConstraint = centerY

        let topPin = searchAreaView.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor)
        topPin.isActive = false
        searchAreaTopPinConstraint = topPin

        let expandedHeight = searchAreaContainerView.heightAnchor.constraint(equalToConstant: Metrics.expandedSearchAreaHeight)
        expandedHeight.isActive = false
        expandedHeightConstraint = expandedHeight
    }

    func setUpExpandedTextViewProperties() {
        aiChatTextView.font = UIFont.daxBodyRegular()
        aiChatTextView.textColor = UIColor(designSystemColor: .textPrimary)
        aiChatTextView.tintColor = fireMode ? UIColor(singleUseColor: .fireModeAccent) : UIColor(designSystemColor: .accent)
        aiChatTextView.autocapitalizationType = .none
        aiChatTextView.autocorrectionType = .no
        aiChatTextView.spellCheckingType = .no
        aiChatTextView.keyboardType = .webSearch
        aiChatTextView.isScrollEnabled = true
    }

    func updateSearchAreaExpansion(animated: Bool) {
        applyTextViewVisibility()
        onSearchAreaExpandedStateChanged?(isSearchAreaExpanded)

        guard animated else {
            searchAreaContainerView.applyShadowOpacityMultiplier(1)
            aiChatSendButton.alpha = isSearchAreaExpanded ? 1 : 0
            if !isSearchAreaExpanded {
                aiChatSendButton.isHidden = true
            }
            applyExpansionConstraints()
            applyExpansionClipping()
            layoutIfNeeded()
            return
        }

        layoutIfNeeded()

        if isSearchAreaExpanded {
            searchAreaContainerView.applyShadowOpacityMultiplier(0)
            applyExpansionClipping()
        }

        applyExpansionConstraints()

        UIView.animate(withDuration: Metrics.expansionAnimationDuration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            if self.isSearchAreaExpanded {
                self.searchAreaContainerView.applyShadowOpacityMultiplier(1)
                self.aiChatSendButton.alpha = 1
            } else {
                self.searchAreaContainerView.applyShadowOpacityMultiplier(0)
                self.aiChatSendButton.alpha = 0
            }
            self.layoutIfNeeded()
        } completion: { _ in
            if !self.isSearchAreaExpanded {
                self.applyExpansionClipping()
                self.searchAreaContainerView.applyShadowOpacityMultiplier(1)
                self.aiChatSendButton.isHidden = true
                self.onCollapseAnimationCompleted?()
                self.onCollapseAnimationCompleted = nil
            } else {
                self.searchAreaContainerView.applyShadowOpacityMultiplier(1)
            }
            if self.isSearchAreaExpanded {
                self.aiChatTextView.becomeFirstResponder()
            }
        }
    }

    private func applyTextViewVisibility() {
        if isSearchAreaExpanded {
            let currentText = textField.text ?? ""
            textField.text = ""
            textField.alpha = currentText.isEmpty ? 1 : 0

            aiChatTextView.text = currentText
            aiChatTextView.isHidden = false
            searchAreaContainerView.bringSubviewToFront(aiChatTextView)

            aiChatSendButton.isHidden = false
            aiChatSendButton.alpha = 0
            searchAreaContainerView.bringSubviewToFront(aiChatSendButton)
            updateAIChatSendButton(hasText: !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else {
            let currentText = aiChatTextView.text ?? ""
            aiChatTextView.isHidden = true
            aiChatTextView.text = ""

            textField.text = currentText
            textField.alpha = 1
        }
    }

    /// Toggles the textField's visibility so its placeholder shows through
    /// the transparent duckAITextView when empty, and hides when there's text.
    func updateTextFieldPlaceholderVisibility(hasText: Bool) {
        guard isSearchAreaExpanded else { return }
        textField.alpha = hasText ? 0 : 1
    }

    func updateAIChatSendButton(hasText: Bool) {
        if hasText {
            aiChatSendButton.setImage(DesignSystemImages.Glyphs.Size24.arrowRightSmall, for: .normal)
            aiChatSendButton.backgroundColor = UIColor(designSystemColor: .accent)
            aiChatSendButton.tintColor = UIColor(designSystemColor: .accentContentPrimary)
            aiChatSendButton.isEnabled = true
        } else if isAIVoiceChatEnabled {
            aiChatSendButton.setImage(DesignSystemImages.Glyphs.Size24.voice, for: .normal)
            aiChatSendButton.backgroundColor = UIColor(designSystemColor: .accent)
            aiChatSendButton.tintColor = UIColor(designSystemColor: .accentContentPrimary)
            aiChatSendButton.isEnabled = true
        } else {
            aiChatSendButton.setImage(DesignSystemImages.Glyphs.Size24.arrowRightSmall, for: .normal)
            aiChatSendButton.backgroundColor = .clear
            aiChatSendButton.tintColor = UIColor(designSystemColor: .icons)
            aiChatSendButton.isEnabled = false
        }
    }

    func updateLeftIconForMode(_ mode: TextEntryMode) {
        switch mode {
        case .aiChat:
            searchAreaView.loupeIconView.image = DesignSystemImages.Glyphs.Size24.aiChat
        case .search:
            searchAreaView.loupeIconView.image = DesignSystemImages.Glyphs.Size24.findSearchSmall
        }
    }

    func setLeftIconHiddenForModeToggle(_ hidden: Bool) {
        searchAreaView.setLeftIconAreaHidden(hidden)
    }

    private func applyExpansionConstraints() {
        if isSearchAreaExpanded {
            searchStackBottomEqualConstraint?.isActive = false
            searchAreaCenterYConstraint?.isActive = false
            searchStackBottomGTEConstraint?.isActive = true
            expandedHeightConstraint?.isActive = true
            searchAreaTopPinConstraint?.isActive = true
        } else {
            expandedHeightConstraint?.isActive = false
            searchAreaTopPinConstraint?.isActive = false
            searchStackBottomGTEConstraint?.isActive = false
            searchStackBottomEqualConstraint?.isActive = true
            searchAreaCenterYConstraint?.isActive = true
        }
    }

    private func applyExpansionClipping() {
        let allowOverflow = isSearchAreaExpanded

        let clippingViews: [UIView] = [self, stackView, searchAreaAlignmentView, searchAreaStackView, searchAreaContainerView]
        clippingViews.forEach { $0.clipsToBounds = !allowOverflow }

        if allowOverflow {
            layer.mask = nil
        } else {
            updateMaskLayer()
        }
    }
}
