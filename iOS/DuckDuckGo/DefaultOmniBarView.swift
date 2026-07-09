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
    var fireButton: UIButton! { fireButtonView }
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

    /// When true, `safeAreaInsets` returns `.zero` because the parent container
    /// (e.g. `OmniBarCell`) already accounts for safe area via its own layout guide constraints.
    /// This prevents the system-calculated insets from shifting during horizontal scrolling.
    var safeAreaManagedByContainer = false

    override var safeAreaInsets: UIEdgeInsets {
        safeAreaManagedByContainer ? .zero : super.safeAreaInsets
    }

    private(set) var layoutMode: OmniBarLayoutMode = .compact

    func setLayoutMode(_ newMode: OmniBarLayoutMode, animated: Bool = false) {
        guard layoutMode != newMode else { return }

        if animated {
            layoutIfNeeded()
            let entering = newMode == .compact
            if entering {
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
                    self.leadingButtonsContainer.alpha = 0
                    self.trailingButtonsContainer.alpha = 0
                    self.applyLayoutMode(newMode)
                    self.layoutIfNeeded()
                }
            } else {
                leadingButtonsContainer.alpha = 0
                trailingButtonsContainer.alpha = 0
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
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
        readableSearchAreaWidthConstraint?.isActive = showButtons && newMode == .expandedPad
        largeSizeSpacingConstraint?.isActive = showButtons

        let isExpandedPhone = newMode == .expandedPhone
        leadingButtonsContainer.spacing = isExpandedPhone ? Metrics.expandedPhoneSizeButtonSpacing : Metrics.iPadButtonSpacing
        trailingButtonsContainer.spacing = isExpandedPhone ? Metrics.expandedPhoneSizeButtonSpacing : Metrics.iPadButtonSpacing
        stackView.spacing = isExpandedPhone ? Metrics.expandedPhoneSizeSpacing : Metrics.expandedPadSizeSpacing
        stackViewLeadingConstraint?.constant = isExpandedPhone ? Metrics.expandedPhoneSizeMargins.leading : Metrics.textAreaHorizontalPadding
        stackViewTrailingConstraint?.constant = isExpandedPhone ? -Metrics.expandedPhoneSizeMargins.trailing : -Metrics.textAreaHorizontalPadding
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
    var onSettingsButtonLongPressed: (() -> Void)?
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
    var longPressMenuProvider: (() -> UIMenu?)? {
        didSet {
            refreshLongPressMenuAvailability()
        }
    }
    var onLongPressMenuDisplayed: (() -> Void)?

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

    let modelPickerButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.down")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        )
        config.imagePlacement = .trailing
        config.imagePadding = Metrics.modelPickerChipSpacing
        config.titleLineBreakMode = .byTruncatingTail
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: Metrics.modelPickerChipHorizontalPadding,
            bottom: 0,
            trailing: Metrics.modelPickerChipHorizontalPadding
        )
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .daxSubheadRegular()
            return updated
        }
        config.background.strokeColor = UIColor(designSystemColor: .lines)
        config.background.strokeWidth = 1
        config.cornerStyle = .capsule

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "AIChat.Omnibar.iPad.ModelPicker"
        button.isHidden = true
        // High (not required) hugging so the leading `>=` constraint wins and the title
        // truncates rather than producing an unsatisfiable layout for long model names.
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        if #available(iOS 16.0, *) {
            button.preferredMenuElementOrder = .fixed
        }
        return button
    }()

    /// Enables the model picker chip (driven by the `iPadDuckAIBarControls` flag).
    var isModelPickerEnabled: Bool = false {
        didSet { refreshModelPickerVisibility() }
    }

    /// The short name shown on the model picker chip. The chip stays hidden while this is empty.
    var aiChatModelName: String? {
        didSet {
            modelPickerButton.configuration?.title = aiChatModelName
            refreshModelPickerVisibility()
        }
    }

    /// The pull-down menu listing selectable models. Setting it enables the chip's primary action.
    var aiChatModelPickerMenu: UIMenu? {
        get { modelPickerButton.menu }
        set {
            modelPickerButton.menu = newValue
            modelPickerButton.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    private var canShowModelPicker: Bool {
        isModelPickerEnabled && !(aiChatModelName?.isEmpty ?? true)
    }

    let reasoningPickerButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "AIChat.Omnibar.iPad.ReasoningPicker"
        button.tintColor = UIColor(designSystemColor: .iconsSecondary)
        button.isHidden = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        if #available(iOS 16.0, *) {
            button.preferredMenuElementOrder = .fixed
        }
        return button
    }()

    /// Enables the reasoning picker chip (driven by the `iPadDuckAIBarControls` flag).
    var isReasoningPickerEnabled: Bool = false {
        didSet { refreshReasoningPickerVisibility() }
    }

    /// The glyph for the selected reasoning mode. The chip stays hidden while this is nil —
    /// i.e. when the selected model doesn't support a reasoning picker.
    var aiChatReasoningIcon: UIImage? {
        didSet {
            reasoningPickerButton.setImage(aiChatReasoningIcon, for: .normal)
            refreshReasoningPickerVisibility()
        }
    }

    /// The pull-down menu listing reasoning modes. Setting it enables the chip's primary action.
    var aiChatReasoningPickerMenu: UIMenu? {
        get { reasoningPickerButton.menu }
        set {
            reasoningPickerButton.menu = newValue
            reasoningPickerButton.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    private var canShowReasoningPicker: Bool {
        isReasoningPickerEnabled && aiChatReasoningIcon != nil
    }

    let toolPickerButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "AIChat.Omnibar.iPad.ToolPicker"
        button.accessibilityLabel = UserText.aiChatToolbarToolsButtonAccessibilityLabel
        button.setImage(DesignSystemImages.Glyphs.Size24.options, for: .normal)
        button.tintColor = UIColor(designSystemColor: .iconsSecondary)
        button.isHidden = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        if #available(iOS 16.0, *) {
            button.preferredMenuElementOrder = .fixed
        }
        return button
    }()

    /// Enables the tool picker chip (driven by the `iPadDuckAIBarControls` flag).
    var isToolPickerEnabled: Bool = false {
        didSet { refreshToolPickerVisibility() }
    }

    /// The pull-down menu listing selectable tools. Setting it enables the chip's primary action;
    /// setting it nil hides the chip — i.e. when the selected model offers no tools.
    var aiChatToolPickerMenu: UIMenu? {
        get { toolPickerButton.menu }
        set {
            toolPickerButton.menu = newValue
            toolPickerButton.showsMenuAsPrimaryAction = (newValue != nil)
            refreshToolPickerVisibility()
        }
    }

    /// Whether a tool is currently selected — tints the chip to signal the active state.
    var isToolSelected: Bool = false {
        didSet {
            toolPickerButton.tintColor = UIColor(designSystemColor: isToolSelected ? .accentPrimary : .iconsSecondary)
        }
    }

    private var canShowToolPicker: Bool {
        isToolPickerEnabled && toolPickerButton.menu != nil
    }

    let attachButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "AIChat.Omnibar.iPad.Attach"
        button.accessibilityLabel = UserText.aiChatToolbarAttachButtonAccessibilityLabel
        button.setImage(DesignSystemImages.Glyphs.Size24.attach, for: .normal)
        button.tintColor = UIColor(designSystemColor: .iconsSecondary)
        button.isHidden = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        if #available(iOS 16.0, *) {
            button.preferredMenuElementOrder = .fixed
        }
        return button
    }()

    /// Enables the attach button (driven by the `iPadDuckAIBarControls` flag).
    var isAttachButtonEnabled: Bool = false {
        didSet { refreshAttachButtonVisibility() }
    }

    /// The menu offering photo / camera / file pickers. Setting it enables the button's primary
    /// action; setting it nil hides the button — i.e. when the selected model accepts no attachments.
    var aiChatAttachmentMenu: UIMenu? {
        get { attachButton.menu }
        set {
            attachButton.menu = newValue
            attachButton.showsMenuAsPrimaryAction = (newValue != nil)
            refreshAttachButtonVisibility()
        }
    }

    private var canShowAttachButton: Bool {
        isAttachButtonEnabled && attachButton.menu != nil
    }

    /// The strip of pending attachments shown above the toolbar row when attachments are present.
    let attachmentsStripView: UnifiedToggleInputAttachmentsStripView = {
        let strip = UnifiedToggleInputAttachmentsStripView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.isHidden = true
        return strip
    }()

    let aiChatTextView: ResignSuppressingTextView = {
        let textView = ResignSuppressingTextView()
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
    private var searchFieldBottomEqualConstraint: NSLayoutConstraint?
    private var searchFieldBottomGTEConstraint: NSLayoutConstraint?
    private var attachmentsStripHeightConstraint: NSLayoutConstraint?
    /// Active when no attachments: the text view fills down to the toolbar row (its default).
    private var textViewBottomToContainerConstraint: NSLayoutConstraint?
    /// Active when attachments are present: the text view stops above the attachments strip.
    private var textViewBottomToStripConstraint: NSLayoutConstraint?
    /// Active when the attach button is shown: the tool picker sits to its trailing edge.
    private var toolPickerLeadingToAttachConstraint: NSLayoutConstraint?
    /// Active when the attach button is hidden: the tool picker aligns to the leading edge instead of
    /// leaving the (hidden) attach button's reserved gap.
    private var toolPickerLeadingToContainerConstraint: NSLayoutConstraint?

    var searchContainerWidth: CGFloat { searchAreaView.frame.width }

    private var masksTop: Bool = true
    private var clipsContent: Bool = true
    private let omniBarProgressView = OmniBarProgressView()
    var progressView: ProgressView? { omniBarProgressView.progressView }

    final class LeadingButtonsContainer: UIStackView { }
    private(set) var leadingButtonsContainer = LeadingButtonsContainer()

    final class TrailingButtonsContainer: UIStackView { }
    private(set) var trailingButtonsContainer = TrailingButtonsContainer()

    private let searchAreaView = DefaultOmniBarSearchView()

    final class SearchAreaContainerView: UIView { }

    // Leaving this as UIView because it could be SearchAreaContainerView or CompositeShadowView
    private let searchAreaContainerView: UIView

    /// Non-nil only when floating UI is disabled; owns the resting pill's composite drop shadow.
    /// When floating UI is enabled the pill background/shadow is provided by the glass (top) or
    /// toolbar capsule (bottom), so no `CompositeShadowView` is added to the hierarchy.
    private let searchAreaShadowView: CompositeShadowView?

    final class FloatingGlassContentHostView: UIView { }
    private let floatingGlassContentHostView = FloatingGlassContentHostView()

    private var omniBarLongPressInteraction: UIContextMenuInteraction?
    private let defaultBackgroundColor = UIColor(designSystemColor: .background)
    private let isFloatingUIEnabled: Bool
    fileprivate var savedBarChromeBackgroundColor: UIColor?
    fileprivate var savedBarViewBackgroundColor: UIColor?

    /// Spans to available width of the omni bar and allows the input field to center horizontally
    final class SearchAreaAlignmentView: UIView { }
    private let searchAreaAlignmentView = SearchAreaAlignmentView()

    final class ActiveOutlineView: UIView { }
    private let activeOutlineView = ActiveOutlineView()

    final class TopLevelStackView: UIStackView { }
    private let stackView = TopLevelStackView()

    private let glassEffect: UIVisualEffectView = {
        let view: UIVisualEffectView
        if #available(iOS 26.0, *) {
            view = UIVisualEffectView(effect: UIGlassEffect())
            view.cornerConfiguration = .capsule()
        } else {
            view = UIVisualEffectView()
        }
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()
    private var floatingHostToContainerConstraints: [NSLayoutConstraint] = []
    private var floatingHostToGlassContentConstraints: [NSLayoutConstraint] = []
    private var chromeContentContainerView: UIView {
        isFloatingUIEnabled ? floatingGlassContentHostView : searchAreaContainerView
    }

    private let opaqueEffect: UIVisualEffectView = {
        let view: UIVisualEffectView
        if #available(iOS 26.0, *) {
            view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            view.cornerConfiguration = .capsule()
        } else {
            view = UIVisualEffectView()
        }
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()

    static func create(isFloatingUIEnabled: Bool) -> Self {
        Self.init(isFloatingUIEnabled: isFloatingUIEnabled)
    }

    static func create() -> Self {
        Self.init(isFloatingUIEnabled: false)
    }

    init(isFloatingUIEnabled: Bool) {
        self.isFloatingUIEnabled = isFloatingUIEnabled
        if isFloatingUIEnabled {
            // Floating UI supplies its own background and shadow (top: glass capsule, bottom:
            // toolbar capsule), so the pill must not carry a CompositeShadowView.
            self.searchAreaContainerView = SearchAreaContainerView()
            self.searchAreaContainerView.backgroundColor = .clear
            self.searchAreaShadowView = nil
        } else {
            let shadowView = CompositeShadowView.defaultShadowView()
            self.searchAreaContainerView = shadowView
            self.searchAreaShadowView = shadowView
        }
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

    func makeGlass() {
        guard isFloatingUIEnabled else {
            makeOpaque()
            return
        }
        glassEffect.removeFromSuperview()
        opaqueEffect.removeFromSuperview()
        glassEffect.frame = searchAreaContainerView.bounds
        searchAreaContainerView.insertSubview(glassEffect, at: 0)
        if floatingGlassContentHostView.superview !== glassEffect.contentView {
            floatingHostToContainerConstraints.forEach { $0.isActive = false }
            floatingGlassContentHostView.removeFromSuperview()
            glassEffect.contentView.addSubview(floatingGlassContentHostView)
            floatingHostToGlassContentConstraints.forEach { $0.isActive = true }
        }
        searchAreaContainerView.backgroundColor = .clear
    }

    func makeOpaque() {
        if isFloatingUIEnabled, floatingGlassContentHostView.superview !== searchAreaContainerView {
            floatingHostToGlassContentConstraints.forEach { $0.isActive = false }
            floatingGlassContentHostView.removeFromSuperview()
            searchAreaContainerView.addSubview(floatingGlassContentHostView)
            floatingHostToContainerConstraints.forEach { $0.isActive = true }
        }
        glassEffect.removeFromSuperview()
        opaqueEffect.removeFromSuperview()
        searchAreaContainerView.backgroundColor = isFloatingUIEnabled
            ? restingFieldBackgroundColor
            : UIColor(designSystemColor: .urlBar)
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

        searchAreaAlignmentView.addSubview(searchAreaContainerView)

        if isFloatingUIEnabled {
            floatingGlassContentHostView.translatesAutoresizingMaskIntoConstraints = false
            searchAreaContainerView.addSubview(floatingGlassContentHostView)
        }

        let chromeContentContainerView = self.chromeContentContainerView
        chromeContentContainerView.addSubview(searchAreaView)
        chromeContentContainerView.addSubview(omniBarProgressView)

        trailingButtonsContainer.addArrangedSubview(fireButtonView)
        trailingButtonsContainer.addArrangedSubview(tabSwitcherContainerView)
        trailingButtonsContainer.addArrangedSubview(bookmarksButtonView)
        trailingButtonsContainer.addArrangedSubview(menuButtonView)
        trailingButtonsContainer.addArrangedSubview(settingsButtonView)

        chromeContentContainerView.addSubview(aiChatTextView)
        chromeContentContainerView.addSubview(aiChatSendButton)
        chromeContentContainerView.addSubview(modelPickerButton)
        chromeContentContainerView.addSubview(reasoningPickerButton)
        chromeContentContainerView.addSubview(toolPickerButton)
        chromeContentContainerView.addSubview(attachButton)
        chromeContentContainerView.addSubview(attachmentsStripView)
        chromeContentContainerView.addSubview(aiChatLeftButton)

        addSubview(activeOutlineView)
        addLayoutGuide(fieldContainerLayoutGuide)
        
        addAIChatFullModeBrandingView()
    }
    
    private func addAIChatFullModeBrandingView() {
        let brandingView = AIChatFullModeOmniBrandingView()
        brandingView.translatesAutoresizingMaskIntoConstraints = false
        chromeContentContainerView.addSubview(brandingView)

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
        searchAreaContainerView.translatesAutoresizingMaskIntoConstraints = false

        let leadingConstraint = stackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Metrics.textAreaHorizontalPadding)
        let trailingConstraint = stackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Metrics.textAreaHorizontalPadding)
        stackViewLeadingConstraint = leadingConstraint
        stackViewTrailingConstraint = trailingConstraint
        if isFloatingUIEnabled {
            floatingHostToContainerConstraints = [
                floatingGlassContentHostView.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor),
                floatingGlassContentHostView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
                floatingGlassContentHostView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),
                floatingGlassContentHostView.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor)
            ]
            floatingHostToGlassContentConstraints = [
                floatingGlassContentHostView.topAnchor.constraint(equalTo: glassEffect.contentView.topAnchor),
                floatingGlassContentHostView.leadingAnchor.constraint(equalTo: glassEffect.contentView.leadingAnchor),
                floatingGlassContentHostView.trailingAnchor.constraint(equalTo: glassEffect.contentView.trailingAnchor),
                floatingGlassContentHostView.bottomAnchor.constraint(equalTo: glassEffect.contentView.bottomAnchor)
            ]
            NSLayoutConstraint.activate(floatingHostToContainerConstraints)
        } else {
            floatingHostToContainerConstraints = []
            floatingHostToGlassContentConstraints = []
        }
        let chromeContentContainerView = self.chromeContentContainerView

        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            textAreaTopPaddingConstraint,
            textAreaBottomPaddingConstraint,

            searchAreaView.topAnchor.constraint(greaterThanOrEqualTo: chromeContentContainerView.topAnchor),
            searchAreaView.bottomAnchor.constraint(lessThanOrEqualTo: chromeContentContainerView.bottomAnchor),
            searchAreaView.leadingAnchor.constraint(equalTo: chromeContentContainerView.leadingAnchor),
            searchAreaView.trailingAnchor.constraint(equalTo: chromeContentContainerView.trailingAnchor),

            searchAreaContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),

            activeOutlineView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor, constant: -Metrics.activeBorderWidth),
            activeOutlineView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor, constant: Metrics.activeBorderWidth),
            activeOutlineView.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor, constant: -Metrics.activeBorderWidth),
            activeOutlineView.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor, constant: Metrics.activeBorderWidth),

            omniBarProgressView.topAnchor.constraint(equalTo: chromeContentContainerView.topAnchor),
            omniBarProgressView.leadingAnchor.constraint(equalTo: chromeContentContainerView.leadingAnchor),
            omniBarProgressView.trailingAnchor.constraint(equalTo: chromeContentContainerView.trailingAnchor),
            omniBarProgressView.bottomAnchor.constraint(equalTo: chromeContentContainerView.bottomAnchor),

            searchAreaContainerView.topAnchor.constraint(equalTo: searchAreaAlignmentView.topAnchor),
            searchAreaContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: searchAreaAlignmentView.leadingAnchor),
            searchAreaContainerView.trailingAnchor.constraint(lessThanOrEqualTo: searchAreaAlignmentView.trailingAnchor),

            // Grow the field as wide as possible; the leading/trailing bounds above plus the
            // centerX constraint below keep it centered within the available width.
            searchAreaContainerView.widthAnchor.constraint(equalTo: widthAnchor).withPriority(.defaultHigh),

            fieldContainerLayoutGuide.leadingAnchor.constraint(equalTo: chromeContentContainerView.leadingAnchor),
            fieldContainerLayoutGuide.trailingAnchor.constraint(equalTo: chromeContentContainerView.trailingAnchor),
            fieldContainerLayoutGuide.topAnchor.constraint(equalTo: chromeContentContainerView.topAnchor),
            fieldContainerLayoutGuide.bottomAnchor.constraint(equalTo: chromeContentContainerView.bottomAnchor)
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
            aiChatLeftButton.leadingAnchor.constraint(equalTo: chromeContentContainerView.leadingAnchor),
            aiChatLeftButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        NSLayoutConstraint.activate(aiChatButtonConstraints)
        
        DefaultOmniBarView.activateItemSizeConstraints(for: aiChatLeftButton)

        // AI Chat mode constraints (inactive by default, activated only in AI Chat mode)
        if let brandingView = aiChatBrandingView {
            aiChatModeConstraints = [
                brandingView.leadingAnchor.constraint(equalTo: chromeContentContainerView.leadingAnchor),
                brandingView.trailingAnchor.constraint(equalTo: chromeContentContainerView.trailingAnchor),
                brandingView.centerYAnchor.constraint(equalTo: chromeContentContainerView.centerYAnchor),
                chromeContentContainerView.widthAnchor.constraint(equalTo: searchAreaAlignmentView.widthAnchor).withPriority(.defaultHigh)
            ]
        }

        setUpExpandedSearchAreaConstraints()
    }

    private func setUpProperties() {

        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        backgroundColor = isFloatingUIEnabled ? .clear : defaultBackgroundColor

        searchAreaAlignmentView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchAreaAlignmentView.setContentCompressionResistancePriority(.required, for: .horizontal)

        searchAreaContainerView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        searchAreaContainerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchAreaContainerView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        searchAreaContainerView.setContentHuggingPriority(.defaultLow, for: .vertical)

        searchAreaContainerView.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)
        searchAreaContainerView.layer.cornerRadius = Metrics.cornerRadius
        searchAreaContainerView.layer.cornerCurve = .continuous

        searchAreaView.layer.cornerRadius = Metrics.cornerRadius
        searchAreaView.layer.cornerCurve = .continuous

        activeOutlineView.isUserInteractionEnabled = false
        activeOutlineView.translatesAutoresizingMaskIntoConstraints = false
        activeOutlineView.layer.borderColor = UIColor(designSystemColor: .accentPrimary).cgColor
        activeOutlineView.layer.borderWidth = Metrics.activeBorderWidth
        activeOutlineView.layer.cornerRadius = Metrics.activeBorderRadius
        activeOutlineView.layer.cornerCurve = .continuous
        activeOutlineView.backgroundColor = .clear

        updateFireModeAppearance()

        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = Metrics.expandedPadSizeSpacing

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

    override func layoutSubviews() {
        super.layoutSubviews()
        applyOmnibarCornerStyle()
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
        settingsButtonView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(settingsButtonLongPress)))

        aiChatLeftButton.addTarget(self, action: #selector(aiChatLeftButtonTap), for: .touchUpInside)
        aiChatSendButton.addTarget(self, action: #selector(aiChatSendButtonTap), for: .primaryActionTriggered)
    }

    private func updateFireModeAppearance() {
        if shouldUseFloatingTopGlass {
            makeGlass()
            activeOutlineView.layer.borderColor = fireMode
                ? UIColor(singleUseColor: .fireModeAccent).cgColor
                : UIColor(designSystemColor: .accentPrimary).cgColor
        } else {
            if fireMode {
                searchAreaContainerView.backgroundColor = UIColor(singleUseColor: .fireModeCardBackground)
                activeOutlineView.layer.borderColor = UIColor(singleUseColor: .fireModeAccent).cgColor
            } else {
                searchAreaContainerView.backgroundColor = restingFieldBackgroundColor
                activeOutlineView.layer.borderColor = UIColor(designSystemColor: .accentPrimary).cgColor
            }
        }
        let style: UIUserInterfaceStyle = fireMode ? .dark : .unspecified
        searchAreaContainerView.subviews.forEach { $0.overrideUserInterfaceStyle = style }
        progressView?.updateFireModeAppearance(fireMode: fireMode)
    }

    private func updateShadows() {
        guard let searchAreaShadowView else { return }
        if isActiveState {
            searchAreaShadowView.applyActiveShadow()
        } else {
            searchAreaShadowView.applyDefaultShadow()
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
        applyOmnibarCornerStyle()
        updateShadows()
    }

    private func updateVerticalSpacing() {
        textAreaTopPaddingConstraint?.constant = isUsingSmallTopSpacing ? Metrics.textAreaTopPaddingAdjustedSpacing : Metrics.textAreaVerticalPaddingRegularSpacing
        textAreaBottomPaddingConstraint?.constant = -(isUsingSmallTopSpacing ? Metrics.textAreaBottomPaddingAdjustedSpacing : Metrics.textAreaVerticalPaddingRegularSpacing)
        // The bottom floating field's resting fill differs from the top; refresh when the position
        // (small-top-spacing) flips, unless fire mode owns the appearance.
        if isFloatingUIEnabled, !fireMode {
            // Don't clobber the top glass with an opaque fill. `makeGlass()` keeps the container
            // clear so the glass effect (behind the content) shows through; only the bottom field
            // takes an opaque resting fill.
            if shouldUseFloatingTopGlass {
                makeGlass()
            } else {
                searchAreaContainerView.backgroundColor = restingFieldBackgroundColor
            }
        }
    }

    func refreshLongPressMenuAvailability() {
        guard longPressMenuProvider != nil else {
            removeOmniBarLongPressInteraction()
            return
        }

        addOmniBarLongPressInteractionIfNeeded()
    }

    func prepareForMoveTransition() {
        backgroundColor = .clear
    }

    func moveTransitionCompleted() {
        backgroundColor = isFloatingUIEnabled ? .clear : defaultBackgroundColor
    }

    private func addOmniBarLongPressInteractionIfNeeded() {
        guard omniBarLongPressInteraction == nil else { return }

        let interaction = UIContextMenuInteraction(delegate: self)
        searchContainer.addInteraction(interaction)
        omniBarLongPressInteraction = interaction
    }

    private func removeOmniBarLongPressInteraction() {
        guard let omniBarLongPressInteraction else { return }
        searchContainer.removeInteraction(omniBarLongPressInteraction)
        self.omniBarLongPressInteraction = nil
    }

    private func overflowTarget(at point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isSearchAreaExpanded else { return nil }
        // The strip and attach button sit above the text view (which is brought to front for typing),
        // so route taps to them before falling back to the text view.
        let candidates: [UIView] = [aiChatSendButton, modelPickerButton, reasoningPickerButton, toolPickerButton, attachButton, attachmentsStripView, aiChatTextView]
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
        if shouldUseFloatingTopGlass {
            let localPoint = floatingGlassContentHostView.convert(point, from: self)
            if let target = floatingGlassContentHostView.hitTest(localPoint, with: event) {
                return target
            }
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

    @objc private func settingsButtonLongPress(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
        onSettingsButtonLongPressed?()
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

    @objc private func menuButtonLongPress(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
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
        static var cornerRadius: CGFloat { OmniBarMetrics.cornerRadius }

        /// Sits 2pt outside `cornerRadius` so the active outline stays concentric with the field.
        static var activeBorderRadius: CGFloat { OmniBarMetrics.cornerRadius + 2 }
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

        // Duck.ai model picker chip (iPad), styled to match the iPhone model chip.
        static let modelPickerChipHeight: CGFloat = 40.0
        static let modelPickerChipHorizontalPadding: CGFloat = 16.0
        static let modelPickerChipSpacing: CGFloat = 4.0
        static let modelPickerToSendButtonSpacing: CGFloat = 8.0

        // Duck.ai reasoning picker chip (iPad), icon-only, sits to the left of the model chip.
        static let reasoningPickerChipSize: CGFloat = 40.0
        static let reasoningToModelPickerSpacing: CGFloat = 4.0
        static let toolPickerChipSize: CGFloat = 40.0

        // Duck.ai attach button (iPad), sits on the far left, to the left of the tool picker.
        static let attachButtonSize: CGFloat = 40.0
        static let attachToToolPickerSpacing: CGFloat = 4.0
        // Vertical gaps around the attachments strip when it grows the expanded search area.
        static let attachmentsStripToButtonRowSpacing: CGFloat = 8.0
        static let attachmentsStripToTextViewSpacing: CGFloat = 4.0

        static let expandedPadSizeSpacing: CGFloat = 24.0
        static let expandedPadSizeMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: expandedPadSizeSpacing,
            bottom: 0,
            trailing: expandedPadSizeSpacing
        )

        static let iPadButtonSpacing: CGFloat = 12.0
        static let expandedPhoneSizeSpacing: CGFloat = 16.0
        static let expandedPhoneSizeButtonSpacing: CGFloat = 10.0
        static let expandedPhoneSizeMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: 4,
            bottom: 0,
            trailing: 4
        )
    }

    private struct Constant {
        static let accessibilityPrefix = "Browser.OmniBar"
    }

    private func applyOmnibarCornerStyle() {
        let cornerRadius: CGFloat
        if isFloatingUIEnabled && isUsingSmallTopSpacing {
            cornerRadius = searchAreaContainerView.bounds.height / 2
        } else {
            cornerRadius = Metrics.cornerRadius
        }

        omniBarProgressView.layer.cornerRadius = cornerRadius
        searchAreaContainerView.layer.cornerRadius = cornerRadius
        searchAreaView.layer.cornerRadius = cornerRadius
        activeOutlineView.layer.cornerRadius = cornerRadius + Metrics.activeBorderWidth
    }
}

private extension DefaultOmniBarView {
    /// Bottom omnibar uses small top spacing. Top position keeps regular spacing.
    var shouldUseFloatingTopGlass: Bool {
        isFloatingUIEnabled && !isUsingSmallTopSpacing
    }

    /// The floating omnibar field when hosted at the bottom (embedded in the toolbar's glass
    /// capsule). Unlike the top position it isn't a glass surface itself, so it takes an explicit
    /// resting fill rather than `.backgroundTertiary`.
    var isBottomFloatingField: Bool {
        isFloatingUIEnabled && isUsingSmallTopSpacing
    }

    /// Resting field fill: the bottom floating field is `T-Input/Resting` so it reads clearly
    /// against the toolbar's Liquid Glass capsule (no shadow needed); otherwise the default fill.
    var restingFieldBackgroundColor: UIColor {
        isBottomFloatingField
            ? UIColor(singleUseColor: .floatingAddressBarBackground)
            : UIColor(designSystemColor: .backgroundTertiary)
    }
}

extension DefaultOmniBarView: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menu = longPressMenuProvider?() else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: { [weak self] in
            self?.makeLongPressMenuPreviewController()
        }) { _ in
            menu
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                animator: UIContextMenuInteractionAnimating?) {
        onLongPressMenuDisplayed?()
    }

    private func makeLongPressMenuPreviewController() -> UIViewController? {
        OmniBarLongPressPreviewViewController(sourceView: searchContainer)
    }
}

private final class OmniBarLongPressPreviewViewController: UIViewController {

    private let sourceView: UIView

    init(sourceView: UIView) {
        self.sourceView = sourceView
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = sourceView.bounds.size
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let containerView = UIView(frame: CGRect(origin: .zero, size: preferredContentSize))
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = false
        view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let snapshotView = sourceView.snapshotView(afterScreenUpdates: false) else { return }

        snapshotView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(snapshotView)

        NSLayoutConstraint.activate([
            snapshotView.topAnchor.constraint(equalTo: view.topAnchor),
            snapshotView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            snapshotView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            snapshotView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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

    func configureForSwipeTemplate(mode: OmniBarLayoutMode, tabCount: Int) {
        setLayoutMode(mode, animated: false)
        tabSwitcherContainerView.subviews.forEach { $0.removeFromSuperview() }
        if mode != .compact {
            let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
            button.translatesAutoresizingMaskIntoConstraints = false
            tabSwitcherContainerView.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: tabSwitcherContainerView.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: tabSwitcherContainerView.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 34),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
            button.tabCount = tabCount
        }
    }

    func hideButtons() {
        privacyInfoContainer.alpha = 0
        searchAreaView.hideButtons()
    }

    func revealButtons() {
        privacyInfoContainer.alpha = 1
        searchAreaView.revealButtons()
    }

    func setIconContainersAlpha(_ alpha: CGFloat) { searchAreaView.setIconContainersAlpha(alpha) }

    func hideBarChrome() {
        if savedBarChromeBackgroundColor == nil {
            savedBarChromeBackgroundColor = searchAreaContainerView.backgroundColor
        }
        if savedBarViewBackgroundColor == nil {
            savedBarViewBackgroundColor = backgroundColor
        }
        searchAreaContainerView.backgroundColor = .clear
        searchAreaShadowView?.applyShadowOpacityMultiplier(0)
        backgroundColor = .clear
        textField.alpha = 0
    }

    func restoreBarChrome() {
        if let saved = savedBarChromeBackgroundColor {
            searchAreaContainerView.backgroundColor = saved
            savedBarChromeBackgroundColor = nil
        }
        if let saved = savedBarViewBackgroundColor {
            backgroundColor = saved
            savedBarViewBackgroundColor = nil
        }
        searchAreaShadowView?.applyShadowOpacityMultiplier(1)
        textField.alpha = 1
    }

    /// Configures the omnibar UI for AI Chat mode. Shows AI Chat buttons, hides search elements.
    private func showAIChatOmnibar() {
        aiChatBrandingView?.isHidden = false
        searchAreaView.textField.isHidden = true
        aiChatLeftButton.isHidden = false
        aiChatLeftButton.alpha = 1.0
        NSLayoutConstraint.activate(aiChatModeConstraints)
        chromeContentContainerView.bringSubviewToFront(aiChatLeftButton)

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
        // The text view fills down to the toolbar row by default; when attachments are present this
        // is swapped for `textViewBottomToStripConstraint` so the text stops above the strip.
        let textBottomToContainer = aiChatTextView.bottomAnchor.constraint(
            equalTo: searchAreaContainerView.bottomAnchor,
            constant: -Metrics.duckAITextViewBottomPadding
        )
        textViewBottomToContainerConstraint = textBottomToContainer

        let textBottomToStrip = aiChatTextView.bottomAnchor.constraint(
            equalTo: attachmentsStripView.topAnchor,
            constant: -Metrics.attachmentsStripToTextViewSpacing
        )
        textBottomToStrip.isActive = false
        textViewBottomToStripConstraint = textBottomToStrip

        let stripHeight = attachmentsStripView.heightAnchor.constraint(equalToConstant: 0)
        attachmentsStripHeightConstraint = stripHeight

        NSLayoutConstraint.activate([
            aiChatTextView.topAnchor.constraint(equalTo: searchAreaView.textField.topAnchor),
            aiChatTextView.leadingAnchor.constraint(equalTo: searchAreaView.textField.leadingAnchor),
            aiChatTextView.trailingAnchor.constraint(equalTo: searchAreaView.textField.trailingAnchor),
            textBottomToContainer,

            aiChatSendButton.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor, constant: -Metrics.duckAITextViewBottomPadding),
            aiChatSendButton.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor, constant: -Metrics.duckAITextViewBottomPadding),
            aiChatSendButton.widthAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
            aiChatSendButton.heightAnchor.constraint(equalToConstant: Metrics.sendButtonSize),

            modelPickerButton.trailingAnchor.constraint(equalTo: aiChatSendButton.leadingAnchor, constant: -Metrics.modelPickerToSendButtonSpacing),
            modelPickerButton.centerYAnchor.constraint(equalTo: aiChatSendButton.centerYAnchor),
            modelPickerButton.heightAnchor.constraint(equalToConstant: Metrics.modelPickerChipHeight),
            modelPickerButton.leadingAnchor.constraint(greaterThanOrEqualTo: aiChatTextView.leadingAnchor),

            reasoningPickerButton.trailingAnchor.constraint(equalTo: modelPickerButton.leadingAnchor, constant: -Metrics.reasoningToModelPickerSpacing),
            reasoningPickerButton.centerYAnchor.constraint(equalTo: aiChatSendButton.centerYAnchor),
            reasoningPickerButton.widthAnchor.constraint(equalToConstant: Metrics.reasoningPickerChipSize),
            reasoningPickerButton.heightAnchor.constraint(equalToConstant: Metrics.reasoningPickerChipSize),
            reasoningPickerButton.leadingAnchor.constraint(greaterThanOrEqualTo: aiChatTextView.leadingAnchor),

            attachButton.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor, constant: Metrics.duckAITextViewBottomPadding),
            attachButton.centerYAnchor.constraint(equalTo: aiChatSendButton.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: Metrics.attachButtonSize),
            attachButton.heightAnchor.constraint(equalToConstant: Metrics.attachButtonSize),

            toolPickerButton.centerYAnchor.constraint(equalTo: aiChatSendButton.centerYAnchor),
            toolPickerButton.widthAnchor.constraint(equalToConstant: Metrics.toolPickerChipSize),
            toolPickerButton.heightAnchor.constraint(equalToConstant: Metrics.toolPickerChipSize),

            attachmentsStripView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor),
            attachmentsStripView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor),
            attachmentsStripView.bottomAnchor.constraint(equalTo: aiChatSendButton.topAnchor, constant: -Metrics.attachmentsStripToButtonRowSpacing),
            stripHeight,
        ])

        // The tool picker normally sits to the trailing edge of the attach button, but when the model
        // accepts no attachments the attach button is hidden while keeping its (constraint-reserved)
        // slot. Toggle between anchoring to the attach button and the leading edge so the tool chip
        // doesn't sit inset behind a hidden button. Kept in sync by `updateToolPickerLeadingConstraint`.
        let toolPickerLeadingToAttach = toolPickerButton.leadingAnchor.constraint(
            equalTo: attachButton.trailingAnchor,
            constant: Metrics.attachToToolPickerSpacing
        )
        toolPickerLeadingToAttachConstraint = toolPickerLeadingToAttach

        let toolPickerLeadingToContainer = toolPickerButton.leadingAnchor.constraint(
            equalTo: searchAreaContainerView.leadingAnchor,
            constant: Metrics.duckAITextViewBottomPadding
        )
        toolPickerLeadingToContainerConstraint = toolPickerLeadingToContainer

        updateToolPickerLeadingConstraint()

        let bottomEqual = searchAreaContainerView.bottomAnchor.constraint(equalTo: searchAreaAlignmentView.bottomAnchor)
        bottomEqual.isActive = true
        searchFieldBottomEqualConstraint = bottomEqual

        let bottomGTE = searchAreaContainerView.bottomAnchor.constraint(greaterThanOrEqualTo: searchAreaAlignmentView.bottomAnchor)
        bottomGTE.isActive = false
        searchFieldBottomGTEConstraint = bottomGTE

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
        aiChatTextView.tintColor = fireMode ? UIColor(singleUseColor: .fireModeAccent) : UIColor(designSystemColor: .accentPrimary)
        aiChatTextView.autocapitalizationType = .none
        aiChatTextView.autocorrectionType = .no
        aiChatTextView.spellCheckingType = .no
        aiChatTextView.keyboardType = .webSearch
        aiChatTextView.isScrollEnabled = true
    }

    func updateSearchAreaExpansion(animated: Bool) {
        applyTextViewVisibility()

        guard animated else {
            searchAreaShadowView?.applyShadowOpacityMultiplier(1)
            aiChatSendButton.alpha = isSearchAreaExpanded ? 1 : 0
            modelPickerButton.alpha = (isSearchAreaExpanded && canShowModelPicker) ? 1 : 0
            reasoningPickerButton.alpha = (isSearchAreaExpanded && canShowReasoningPicker) ? 1 : 0
            toolPickerButton.alpha = (isSearchAreaExpanded && canShowToolPicker) ? 1 : 0
            attachButton.alpha = (isSearchAreaExpanded && canShowAttachButton) ? 1 : 0
            if !isSearchAreaExpanded {
                aiChatSendButton.isHidden = true
                modelPickerButton.isHidden = true
                reasoningPickerButton.isHidden = true
                toolPickerButton.isHidden = true
                attachButton.isHidden = true
            }
            applyExpansionConstraints()
            let showStrip = applyAttachmentsConstraints()
            attachmentsStripView.alpha = showStrip ? 1 : 0
            applyExpansionClipping()
            layoutIfNeeded()
            if !showStrip {
                attachmentsStripView.isHidden = true
            }
            // After layout so observers (the popover) anchor against the final frame.
            onSearchAreaExpandedStateChanged?(isSearchAreaExpanded)
            if isSearchAreaExpanded, !aiChatTextView.isFirstResponder {
                aiChatTextView.becomeFirstResponder()
            }
            return
        }

        // Collapsing: notify now so the popover hides as the bar shrinks. Expanding: notify on completion
        // (below), once the expanded frame is laid out, so the popover anchors at the right Y instead of
        // sliding from the collapsed position.
        if !isSearchAreaExpanded {
            onSearchAreaExpandedStateChanged?(false)
        }

        layoutIfNeeded()

        if isSearchAreaExpanded {
            searchAreaShadowView?.applyShadowOpacityMultiplier(0)
            applyExpansionClipping()
        }

        applyExpansionConstraints()
        let showStrip = applyAttachmentsConstraints()

        UIView.animate(withDuration: Metrics.expansionAnimationDuration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            if self.isSearchAreaExpanded {
                self.searchAreaShadowView?.applyShadowOpacityMultiplier(1)
                self.aiChatSendButton.alpha = 1
                self.modelPickerButton.alpha = self.canShowModelPicker ? 1 : 0
                self.reasoningPickerButton.alpha = self.canShowReasoningPicker ? 1 : 0
                self.toolPickerButton.alpha = self.canShowToolPicker ? 1 : 0
                self.attachButton.alpha = self.canShowAttachButton ? 1 : 0
            } else {
                self.searchAreaShadowView?.applyShadowOpacityMultiplier(0)
                self.aiChatSendButton.alpha = 0
                self.modelPickerButton.alpha = 0
                self.reasoningPickerButton.alpha = 0
                self.toolPickerButton.alpha = 0
                self.attachButton.alpha = 0
            }
            self.attachmentsStripView.alpha = showStrip ? 1 : 0
            self.layoutIfNeeded()
        } completion: { _ in
            if !showStrip {
                self.attachmentsStripView.isHidden = true
            }
            if !self.isSearchAreaExpanded {
                self.applyExpansionClipping()
                self.searchAreaShadowView?.applyShadowOpacityMultiplier(1)
                self.aiChatSendButton.isHidden = true
                self.modelPickerButton.isHidden = true
                self.reasoningPickerButton.isHidden = true
                self.toolPickerButton.isHidden = true
                self.attachButton.isHidden = true
                self.onCollapseAnimationCompleted?()
                self.onCollapseAnimationCompleted = nil
            } else {
                self.searchAreaShadowView?.applyShadowOpacityMultiplier(1)
                self.onSearchAreaExpandedStateChanged?(true)
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
            chromeContentContainerView.bringSubviewToFront(aiChatTextView)

            aiChatSendButton.isHidden = false
            aiChatSendButton.alpha = 0
            chromeContentContainerView.bringSubviewToFront(aiChatSendButton)
            updateAIChatSendButton(hasText: !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if canShowModelPicker {
                prepareModelPickerButtonForDisplay()
            }

            if canShowReasoningPicker {
                reasoningPickerButton.isHidden = false
                reasoningPickerButton.alpha = 0
                searchAreaContainerView.bringSubviewToFront(reasoningPickerButton)
            }

            if canShowToolPicker {
                toolPickerButton.isHidden = false
                toolPickerButton.alpha = 0
                searchAreaContainerView.bringSubviewToFront(toolPickerButton)
            }

            if canShowAttachButton {
                attachButton.isHidden = false
                attachButton.alpha = 0
                searchAreaContainerView.bringSubviewToFront(attachButton)
            }
        } else {
            let currentText = aiChatTextView.text ?? ""
            aiChatTextView.isHidden = true
            aiChatTextView.text = ""

            textField.text = currentText
            textField.alpha = 1
        }
    }

    private func refreshModelPickerVisibility() {
        guard isSearchAreaExpanded, canShowModelPicker else {
            modelPickerButton.isHidden = true
            return
        }
        guard modelPickerButton.isHidden else { return }
        prepareModelPickerButtonForDisplay()
        UIView.animate(withDuration: Metrics.expansionAnimationDuration) {
            self.modelPickerButton.alpha = 1
        }
    }

    private func prepareModelPickerButtonForDisplay() {
        modelPickerButton.isHidden = false
        modelPickerButton.alpha = 0
        chromeContentContainerView.bringSubviewToFront(modelPickerButton)
    }

    private func refreshReasoningPickerVisibility() {
        guard isSearchAreaExpanded, canShowReasoningPicker else {
            reasoningPickerButton.isHidden = true
            return
        }
        guard reasoningPickerButton.isHidden else { return }
        reasoningPickerButton.isHidden = false
        reasoningPickerButton.alpha = 0
        searchAreaContainerView.bringSubviewToFront(reasoningPickerButton)
        UIView.animate(withDuration: Metrics.expansionAnimationDuration) {
            self.reasoningPickerButton.alpha = 1
        }
    }

    private func refreshToolPickerVisibility() {
        guard isSearchAreaExpanded, canShowToolPicker else {
            toolPickerButton.isHidden = true
            return
        }
        guard toolPickerButton.isHidden else { return }
        toolPickerButton.isHidden = false
        toolPickerButton.alpha = 0
        searchAreaContainerView.bringSubviewToFront(toolPickerButton)
        UIView.animate(withDuration: Metrics.expansionAnimationDuration) {
            self.toolPickerButton.alpha = 1
        }
    }

    private func refreshAttachButtonVisibility() {
        // Attach availability drives where the tool picker anchors, so re-evaluate it on every call
        // (including the early-return paths below).
        updateToolPickerLeadingConstraint()
        guard isSearchAreaExpanded, canShowAttachButton else {
            attachButton.isHidden = true
            return
        }
        guard attachButton.isHidden else { return }
        attachButton.isHidden = false
        attachButton.alpha = 0
        searchAreaContainerView.bringSubviewToFront(attachButton)
        UIView.animate(withDuration: Metrics.expansionAnimationDuration) {
            self.attachButton.alpha = 1
        }
    }

    /// Anchors the tool picker to the attach button's trailing edge when the attach button is shown,
    /// or to the leading edge when it is hidden (so the hidden button's reserved slot doesn't push
    /// the tool chip inward). No-op until `setUpExpandedSearchAreaConstraints` creates the constraints.
    private func updateToolPickerLeadingConstraint() {
        guard let toAttach = toolPickerLeadingToAttachConstraint,
              let toContainer = toolPickerLeadingToContainerConstraint else { return }
        let attachVisible = canShowAttachButton
        toAttach.isActive = attachVisible
        toContainer.isActive = !attachVisible
    }

    /// Sets the strip height, text-view bottom anchor, and expanded-area growth for the current
    /// attachments and expansion state, without animating. Returns whether the strip should be shown.
    /// The `expandedHeightConstraint` is only active while expanded, so this is inert when collapsed.
    @discardableResult
    private func applyAttachmentsConstraints() -> Bool {
        let showStrip = isSearchAreaExpanded && !attachmentsStripView.attachments.isEmpty
        let stripHeight = showStrip ? UnifiedToggleInputAttachmentsStripView.Constants.stripHeight : 0
        let growth = showStrip
            ? stripHeight + Metrics.attachmentsStripToButtonRowSpacing + Metrics.attachmentsStripToTextViewSpacing
            : 0

        attachmentsStripHeightConstraint?.constant = stripHeight
        expandedHeightConstraint?.constant = Metrics.expandedSearchAreaHeight + growth

        textViewBottomToContainerConstraint?.isActive = !showStrip
        textViewBottomToStripConstraint?.isActive = showStrip

        if showStrip {
            attachmentsStripView.isHidden = false
            searchAreaContainerView.bringSubviewToFront(attachmentsStripView)
        }
        return showStrip
    }

    /// Grows the expanded search area to fit the attachments strip when attachments are present, and
    /// collapses it back when empty. Called by the omnibar controller whenever the strip changes.
    func updateAttachmentsLayout(animated: Bool) {
        let showStrip = applyAttachmentsConstraints()

        guard animated else {
            attachmentsStripView.alpha = showStrip ? 1 : 0
            layoutIfNeeded()
            if !showStrip {
                attachmentsStripView.isHidden = true
            }
            return
        }

        UIView.animate(withDuration: Metrics.expansionAnimationDuration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.attachmentsStripView.alpha = showStrip ? 1 : 0
            self.layoutIfNeeded()
        } completion: { _ in
            if !showStrip {
                self.attachmentsStripView.isHidden = true
            }
        }
    }

    /// Toggles the textField's visibility so its placeholder shows through
    /// the transparent duckAITextView when empty, and hides when there's text.
    func updateTextFieldPlaceholderVisibility(hasText: Bool) {
        guard isSearchAreaExpanded else { return }
        textField.alpha = hasText ? 0 : 1
    }

    func updateAIChatSendButton(hasText: Bool) {
        // Mirror the iPhone unified toggle rule: submit is available with text or a valid attachment,
        // and blocked while any attachment is invalid. Voice only stands in when the input is truly
        // empty (no text and no attachments).
        let attachments = attachmentsStripView.attachments
        let hasValidAttachment = attachments.contains { !$0.isInvalid }
        let hasInvalidAttachment = attachments.contains(where: \.isInvalid)
        let canSubmit = !hasInvalidAttachment && (hasText || hasValidAttachment)
        let accentColor = fireMode ? UIColor(singleUseColor: .fireModeAccent) : UIColor(designSystemColor: .accentPrimary)
        if canSubmit {
            aiChatSendButton.setImage(DesignSystemImages.Glyphs.Size24.arrowRightSmall, for: .normal)
            aiChatSendButton.backgroundColor = accentColor
            aiChatSendButton.tintColor = UIColor(designSystemColor: .accentContentPrimary)
            aiChatSendButton.isEnabled = true
        } else if !hasText && attachments.isEmpty && isAIVoiceChatEnabled {
            aiChatSendButton.setImage(DesignSystemImages.Glyphs.Size24.voice, for: .normal)
            aiChatSendButton.backgroundColor = accentColor
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
            searchFieldBottomEqualConstraint?.isActive = false
            searchAreaCenterYConstraint?.isActive = false
            searchFieldBottomGTEConstraint?.isActive = true
            expandedHeightConstraint?.isActive = true
            searchAreaTopPinConstraint?.isActive = true
        } else {
            expandedHeightConstraint?.isActive = false
            searchAreaTopPinConstraint?.isActive = false
            searchFieldBottomGTEConstraint?.isActive = false
            searchFieldBottomEqualConstraint?.isActive = true
            searchAreaCenterYConstraint?.isActive = true
        }
    }

    private func applyExpansionClipping() {
        let allowOverflow = isSearchAreaExpanded

        let clippingViews: [UIView] = [self, stackView, searchAreaAlignmentView, searchAreaContainerView]
        clippingViews.forEach { $0.clipsToBounds = !allowOverflow }

        if allowOverflow {
            layer.mask = nil
        } else {
            updateMaskLayer()
        }
    }
}

/// A `UITextView` that can be prevented from resigning first responder,
final class ResignSuppressingTextView: UITextView {

    /// When true, prevents the text view from resigning first responder.
    /// Used during device rotation to keep the keyboard visible.
    var suppressResignFirstResponder: Bool = false

    @discardableResult
    override func resignFirstResponder() -> Bool {
        if suppressResignFirstResponder { return false }
        return super.resignFirstResponder()
    }
}

#if DEBUG
final class RebrandPreviewOverride: ObservableObject {
    private let isRebranded: Bool
    private let previousAppRebrand: () -> Bool
    private let previousDesignSystemRebrand: () -> Bool
    private let previousPalette: ColorPalette

    init(isRebranded: Bool) {
        self.isRebranded = isRebranded
        previousAppRebrand = AppRebrand.isAppRebranded
        previousDesignSystemRebrand = DesignSystemRebrand.isAppRebranded
        previousPalette = DesignSystemPalette.current
        apply()
    }

    func apply() {
        AppRebrand.isAppRebranded = { [isRebranded] in isRebranded }
        DesignSystemRebrand.isAppRebranded = { [isRebranded] in isRebranded }
        DesignSystemPalette.current = isRebranded ? .rebranded : .default
    }

    deinit {
        AppRebrand.isAppRebranded = previousAppRebrand
        DesignSystemRebrand.isAppRebranded = previousDesignSystemRebrand
        DesignSystemPalette.current = previousPalette
    }
}

/// Bridges the UIKit ``DefaultOmniBarView`` into SwiftUI so it can be shown in a `#Preview`.
private struct DefaultOmniBarViewRepresentable: UIViewRepresentable {
    let omniBarView: DefaultOmniBarView

    func makeUIView(context: Context) -> DefaultOmniBarView { omniBarView }
    func updateUIView(_ uiView: DefaultOmniBarView, context: Context) {}
}

private struct DefaultOmniBarViewGallery: View {
    @StateObject private var rebrandOverride: RebrandPreviewOverride

    init(isRebranded: Bool) {
        _rebrandOverride = StateObject(wrappedValue: RebrandPreviewOverride(isRebranded: isRebranded))
    }

    var body: some View {
        rebrandOverride.apply()
        return DefaultOmniBarViewRepresentable(omniBarView: DefaultOmniBarView(isFloatingUIEnabled: false))
            .frame(width: 360, height: 60)
            .padding()
    }
}

#Preview("Address bar / Legacy") {
    DefaultOmniBarViewGallery(isRebranded: false)
}

#Preview("Address bar / Rebranded") {
    DefaultOmniBarViewGallery(isRebranded: true)
}
#endif
