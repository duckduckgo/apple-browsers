//
//  AIChatContextualInputViewController.swift
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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

// MARK: - Delegate Protocol

/// Delegate protocol for handling user interactions with the contextual input view controller.
protocol AIChatContextualInputViewControllerDelegate: AnyObject {
    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSubmitPrompt prompt: String)
    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSelectQuickAction action: AIChatContextualQuickAction)
    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSelectSuggestion suggestion: ContextualSuggestedPrompt)
    func contextualInputViewControllerDidTapVoice(_ viewController: AIChatContextualInputViewController)
    func contextualInputViewControllerDidRemoveContextChip(_ viewController: AIChatContextualInputViewController)
    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didTapLink url: URL)
}

// MARK: - Input Surface

protocol AIChatContextualInputSurface {
    @discardableResult func becomeFirstResponder() -> Bool
    @discardableResult func resignFirstResponder() -> Bool
    var isContextChipVisible: Bool { get }
    func setText(_ text: String)
    func appendText(_ text: String)
    func showContextChip(_ chipView: UIView)
    func hideContextChip()
    func updateContextChipState(_ state: AIChatContextChipView.State)
    func setChipTapCallback(_ callback: @escaping () -> Void)
}

private struct NoContextualInputSurface: AIChatContextualInputSurface {
    var isContextChipVisible: Bool { false }
    func becomeFirstResponder() -> Bool { false }
    func resignFirstResponder() -> Bool { false }
    func setText(_ text: String) {}
    func appendText(_ text: String) {}
    func showContextChip(_ chipView: UIView) {}
    func hideContextChip() {}
    func updateContextChipState(_ state: AIChatContextChipView.State) {}
    func setChipTapCallback(_ callback: @escaping () -> Void) {}
}

extension AIChatBasicNativeInputViewController: AIChatContextualInputSurface {}

// MARK: - View Controller

/// Container view controller that hosts the basic native input and handles keyboard adjustments.
final class AIChatContextualInputViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let horizontalPadding: CGFloat = 20
        static let quickActionsBottomSpacing: CGFloat = 12
        static let keyboardSpacing: CGFloat = 20
        /// A hardware keyboard's shortcuts bar covers less than this, so it never floats the suggestions.
        static let floatingKeyboardOverlap: CGFloat = 150
        static let startActionsEdgeFadeLength: CGFloat = 24
        static let iPadBottomPadding: CGFloat = 16
        static let dimmedStartActionsAlpha: CGFloat = 0.4
    }

    // MARK: - Properties

    weak var delegate: AIChatContextualInputViewControllerDelegate?

    private let showsBasicNativeInput: Bool
    private let showsWelcomeMessage: Bool
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let termsOfServiceDisclaimer: DuckAiTermsOfServiceDisclaimer
    private let inputOutcomeMeasurement: DuckAiInputOutcomeMeasurement
    private lazy var basicNativeInputViewController = AIChatBasicNativeInputViewController(voiceSearchHelper: voiceSearchHelper)
    private lazy var inputSurface: AIChatContextualInputSurface = {
        if showsBasicNativeInput {
            return basicNativeInputViewController
        } else {
            return NoContextualInputSurface()
        }
    }()

    private lazy var quickActionsScrollView: StartActionsScrollView = {
        let scrollView = StartActionsScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var quickActionsView: AIChatQuickActionsView<ContextualSheetAction> = {
        let view = AIChatQuickActionsView<ContextualSheetAction>()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }()

    private lazy var welcomeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Sits behind the basic native input and shows below it, like the UTI's footer card.
    private lazy var termsOfServiceCard: UTIFooterCardView = {
        let card = UTIFooterCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.isHidden = true
        card.onLinkTap = { [weak self] url in
            guard let self else { return }
            delegate?.contextualInputViewController(self, didTapLink: url)
        }
        return card
    }()

    private var welcomeCenterYConstraint: NSLayoutConstraint?
    private var startActionsLeadingConstraint: NSLayoutConstraint?
    private var startActionsTrailingConstraint: NSLayoutConstraint?
    /// Pins the input to the keyboard while the disclaimer is hidden.
    private var bottomConstraint: NSLayoutConstraint?
    /// Pins the disclaimer, and the input above it, to the keyboard while it shows.
    private var termsOfServiceBottomConstraint: NSLayoutConstraint?
    private var bottomInset: CGFloat = 0 {
        didSet {
            bottomConstraint?.constant = bottomInset
            termsOfServiceBottomConstraint?.constant = bottomInset
        }
    }
    private var displayedTermsOfServiceMessage: UTIFooterMessage?
    private var renderedStartActions: [ContextualSheetAction] = []
    private var lastStartActionsHeight: CGFloat = 0
    private lazy var startActionsEdgeFadeMask = CAGradientLayer()

    /// The sidebar column the suggestions float beside while a keyboard covers it, or nil when this input is not in one.
    var floatingSuggestionsColumn: () -> UIView? = { nil }

    private(set) var isFloatingSuggestions = false
    /// A sent prompt's chat is about to replace this input, so its suggestions must not come back in the meantime.
    private var isAwaitingSubmittedChat = false
    /// The prompt typed into a host's own input, which replaces the basic one.
    private var hostInputText = ""
    private var inputText: String {
        showsBasicNativeInput ? basicNativeInputViewController.text : hostInputText
    }
    /// Where the column's chips sat with no keyboard up, in this view's space, so the floating chips take off from there.
    private var restingStartActionFrames: [CGRect] = []
    /// From the keyboard's notifications: the window's keyboard guide is never laid out, so it can't tell.
    private var isKeyboardCoveringColumn = false
    private var isRestingStartActionFramesRecordPending = false
    /// While the floating chips fly home, the column's list waits for them to land before it reappears.
    private var isLandingFloatingSuggestions = false
    private lazy var floatingSuggestionsView: AIChatContextualFloatingSuggestionsView = {
        let view = AIChatContextualFloatingSuggestionsView()
        view.onActionSelected = { [weak self] action in self?.didSelectStartAction(action) }
        return view
    }()

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol,
         showsBasicNativeInput: Bool = true,
         showsWelcomeMessage: Bool = true,
         termsOfServiceDisclaimer: DuckAiTermsOfServiceDisclaimer = DuckAiTermsOfServiceDisclaimer(),
         inputOutcomePixelFiring: DuckAiInputOutcomePixelFiring = DuckAiInputOutcomePixelAdapter()) {
        self.showsBasicNativeInput = showsBasicNativeInput
        self.showsWelcomeMessage = showsWelcomeMessage
        self.voiceSearchHelper = voiceSearchHelper
        self.termsOfServiceDisclaimer = termsOfServiceDisclaimer
        self.inputOutcomeMeasurement = DuckAiInputOutcomeMeasurement(pixelFiring: inputOutcomePixelFiring)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        if showsBasicNativeInput {
            configureBasicNativeInput()
            setupAppLifecycleObservers()
            refreshTermsOfServiceDisclaimer()
        }
        configureQuickActions()
        setupKeyboardObservers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWelcomeLabelCentering()
        recordRestingStartActionFramesAfterThisPass()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBottomPaddingForOrientation()
        refreshTermsOfServiceDisclaimer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startInputOutcomeMeasurement()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resetFloatingSuggestions(animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        inputOutcomeMeasurement.inputClosed()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateBottomPaddingForOrientation()
        })
    }

    // MARK: - Public Methods

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        inputSurface.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        inputSurface.resignFirstResponder()
    }

    var isContextChipVisible: Bool {
        inputSurface.isContextChipVisible
    }

    func setText(_ text: String) {
        inputSurface.setText(text)
    }

    func appendText(_ text: String) {
        inputSurface.appendText(text)
    }

    func showContextChip(_ chipView: UIView) {
        inputSurface.showContextChip(chipView)
    }

    func hideContextChip() {
        inputSurface.hideContextChip()
    }

    func updateContextChipState(_ state: AIChatContextChipView.State) {
        inputSurface.updateContextChipState(state)
    }

    func setChipTapCallback(_ callback: @escaping () -> Void) {
        inputSurface.setChipTapCallback(callback)
    }

    func updateStartActions(suggestions: [ContextualSuggestedPrompt], quickActions: [AIChatContextualQuickAction]) {
        let actions = suggestions.map(ContextualSheetAction.suggestion)
            + quickActions.map(ContextualSheetAction.quickAction)
        guard actions != renderedStartActions else { return }
        renderedStartActions = actions
        quickActionsView.configure(with: actions)
        floatingSuggestionsView.configure(with: actions)
        view.layoutIfNeeded()
        recordRestingStartActionFramesAfterThisPass()
    }

    func updateSuggestionsLoading(_ isLoading: Bool) {
        quickActionsView.setLoading(isLoading)
        floatingSuggestionsView.setLoading(isLoading)
    }

    /// Puts the start actions back in the column at once, e.g. when the surface leaves the sidebar.
    func resetFloatingSuggestions(animated: Bool = false) {
        guard isFloatingSuggestions else { return }
        // The column is going away with this input, so floating chips fade rather than fly home into it.
        setFloatingSuggestions(false, animation: nil, animatesFloatingSuggestions: animated, returnsToColumn: false)
    }

    /// Clipping is released because interactive glass scales a chip past its bounds on touch. Safe here:
    /// the scroll view is sized to its content, so it only scrolls when the screen runs out of room.
    func useGlassStartActionBackgrounds() {
        quickActionsView.chipBackgroundStyle = .glass
        quickActionsScrollView.clipsToBounds = false
        quickActionsView.clipsToBounds = false
    }

    var startActionCount: Int {
        quickActionsView.chipCount
    }

    func showStartActions() {
        quickActionsView.showChips()
    }

    /// Removes this controller's own horizontal inset so a host can align the chips itself.
    func clearStartActionsHorizontalInset() {
        startActionsLeadingConstraint?.constant = 0
        startActionsTrailingConstraint?.constant = 0
    }

    /// Whether `point`, expressed in `view`'s coordinate space, lands on a chip rather than the gaps
    /// around them. Lets a host pass taps in the empty areas through to whatever sits behind.
    func containsStartAction(at point: CGPoint, from view: UIView) -> Bool {
        !self.view.isHidden && quickActionsView.containsChip(at: point, from: view)
    }

    /// Call when a prompt is sent: in the sidebar, the suggestions leave instead of returning as the input empties.
    func hideStartActionsForSubmittedPrompt() {
        guard floatingSuggestionsColumn() != nil else { return }
        isAwaitingSubmittedChat = true
        resetFloatingSuggestions(animated: true)
        UIView.animate(withDuration: 0.2) {
            self.updateStartActionsVisibility()
        }
    }

    /// Call when the input is back for a new chat.
    func showStartActionsForNewChat() {
        guard isAwaitingSubmittedChat else { return }
        isAwaitingSubmittedChat = false
        updateStartActionsVisibility()
    }

    /// For a host whose own input replaces the basic one, so floating suggestions step aside while a prompt is typed.
    func hostInputTextDidChange(_ text: String) {
        hostInputText = text
        updateStartActionsVisibilityForText()
    }

    func setStartActionsDimmed(_ dimmed: Bool) {
        quickActionsView.alpha = dimmed ? Constants.dimmedStartActionsAlpha : 1
        quickActionsView.isUserInteractionEnabled = !dimmed
        floatingSuggestionsView.setDimmed(dimmed)
    }

    /// Call only for an Ask tap: sending with the disclaimer on screen is the acceptance, a chip never is.
    /// Returns whether the terms are accepted afterwards, on this tap or an earlier one.
    @discardableResult
    func acceptTermsIfDisclaimerShown() -> Bool {
        if termsOfServiceDisclaimer.acceptIfShown(visibleTermsOfServiceMessage) {
            refreshTermsOfServiceDisclaimer()
        }
        return termsOfServiceDisclaimer.hasAccepted
    }

    /// Call before `acceptTermsIfDisclaimerShown()`, for every prompt the basic input sends.
    func recordInputOutcome(_ outcome: DuckAiInputOutcome) {
        inputOutcomeMeasurement.record(outcome)
    }

    /// The basic input shows only before the sheet's chat has a prompt, so every opening here starts a new chat.
    private func startInputOutcomeMeasurement() {
        guard showsBasicNativeInput, viewIfLoaded?.window != nil else { return }
        inputOutcomeMeasurement.inputOpened(surface: .contextualChat,
                                            isTermsOfServiceDisclaimerShown: visibleTermsOfServiceMessage != nil)
    }

    private var visibleTermsOfServiceMessage: UTIFooterMessage? {
        guard viewIfLoaded?.window != nil else { return nil }
        return displayedTermsOfServiceMessage
    }

}

// MARK: - Private Setup

private extension AIChatContextualInputViewController {

    func setupUI() {
        view.backgroundColor = .clear

        if showsBasicNativeInput {
            setupImprovedUI()
        } else {
            setupImmediateUTIUI()
        }
    }

    func setupOriginalUI() {
        view.addSubview(quickActionsScrollView)
        quickActionsScrollView.addSubview(quickActionsView)
        embedBasicNativeInputViewController()

        bottomConstraint = basicNativeInputViewController.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)

        NSLayoutConstraint.activate([
            quickActionsScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            quickActionsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            quickActionsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            quickActionsScrollView.bottomAnchor.constraint(equalTo: basicNativeInputViewController.view.topAnchor, constant: -Constants.quickActionsBottomSpacing),

            quickActionsView.topAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.topAnchor),
            quickActionsView.leadingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.leadingAnchor),
            quickActionsView.trailingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.trailingAnchor),
            quickActionsView.bottomAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.bottomAnchor),
            quickActionsView.widthAnchor.constraint(equalTo: quickActionsScrollView.frameLayoutGuide.widthAnchor),
            quickActionsView.heightAnchor.constraint(greaterThanOrEqualTo: quickActionsScrollView.frameLayoutGuide.heightAnchor),

            basicNativeInputViewController.view.topAnchor.constraint(greaterThanOrEqualTo: quickActionsView.bottomAnchor, constant: Constants.quickActionsBottomSpacing),
            basicNativeInputViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            basicNativeInputViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            bottomConstraint!,
        ])
    }

    func setupImprovedUI() {
        view.addSubview(quickActionsScrollView)
        quickActionsScrollView.addSubview(quickActionsView)
        view.addSubview(welcomeLabel)
        embedBasicNativeInputViewController()
        view.insertSubview(termsOfServiceCard, belowSubview: basicNativeInputViewController.view)

        configureWelcomeLabel()

        bottomConstraint = basicNativeInputViewController.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        termsOfServiceBottomConstraint = termsOfServiceCard.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)

        let centerY = welcomeLabel.centerYAnchor.constraint(equalTo: view.topAnchor)
        centerY.priority = .defaultHigh
        welcomeCenterYConstraint = centerY

        NSLayoutConstraint.activate(startActionsConstraints(above: basicNativeInputViewController.view.topAnchor) + [
            // Welcome label centered horizontally, vertical position set dynamically
            centerY,
            welcomeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            welcomeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            welcomeLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Constants.horizontalPadding),

            basicNativeInputViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            basicNativeInputViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            bottomConstraint!,

            termsOfServiceCard.topAnchor.constraint(equalTo: basicNativeInputViewController.view.bottomAnchor,
                                                    constant: -UTIFooterCardView.overlap),
            termsOfServiceCard.leadingAnchor.constraint(equalTo: basicNativeInputViewController.view.leadingAnchor),
            termsOfServiceCard.trailingAnchor.constraint(equalTo: basicNativeInputViewController.view.trailingAnchor),
        ])
    }

    /// Re-read whenever the input comes on screen: the user may have accepted on the web since.
    func refreshTermsOfServiceDisclaimer() {
        guard showsBasicNativeInput else { return }
        // The basic input has no tool picker, so Create Image never applies here.
        let message = termsOfServiceDisclaimer.message(sendButton: .ask)
        if let message {
            termsOfServiceCard.configure(with: message, animateIcon: false)
        }
        displayedTermsOfServiceMessage = message
        termsOfServiceCard.isHidden = message == nil
        if visibleTermsOfServiceMessage != nil { inputOutcomeMeasurement.termsOfServiceDisclaimerBecameVisible() }
        basicNativeInputViewController.submitButtonTitle = message == nil ? nil : UserText.duckAIAskButtonTitle

        // The outgoing pin goes first, so the two are never active together.
        let (outgoing, incoming) = message == nil
            ? (termsOfServiceBottomConstraint, bottomConstraint)
            : (bottomConstraint, termsOfServiceBottomConstraint)
        outgoing?.isActive = false
        incoming?.isActive = true
    }

    func setupImmediateUTIUI() {
        view.addSubview(quickActionsScrollView)
        quickActionsScrollView.addSubview(quickActionsView)
        view.addSubview(welcomeLabel)

        configureWelcomeLabel()

        let centerY = welcomeLabel.centerYAnchor.constraint(equalTo: view.topAnchor)
        centerY.priority = .defaultHigh
        welcomeCenterYConstraint = centerY

        NSLayoutConstraint.activate(startActionsConstraints(above: view.bottomAnchor) + [
            centerY,
            welcomeLabel.bottomAnchor.constraint(lessThanOrEqualTo: quickActionsScrollView.topAnchor, constant: -Constants.quickActionsBottomSpacing),
            welcomeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            welcomeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            welcomeLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
        ])
    }

    /// Sized to the chips until the space above `bottom` runs out; then the list scrolls instead of growing upwards.
    func startActionsConstraints(above bottom: NSLayoutYAxisAnchor) -> [NSLayoutConstraint] {
        quickActionsScrollView.onLayout = { [weak self] in
            self?.keepNearestStartActionsVisible()
            self?.updateStartActionsEdgeFade()
            self?.recordRestingStartActionFramesAfterThisPass()
        }
        let fitContent = quickActionsScrollView.frameLayoutGuide.heightAnchor.constraint(
            equalTo: quickActionsScrollView.contentLayoutGuide.heightAnchor)
        fitContent.priority = .defaultHigh
        let leading = quickActionsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalPadding)
        startActionsLeadingConstraint = leading
        let trailing = quickActionsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.horizontalPadding)
        startActionsTrailingConstraint = trailing
        return [
            quickActionsScrollView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            leading,
            trailing,
            quickActionsScrollView.bottomAnchor.constraint(equalTo: bottom, constant: -Constants.quickActionsBottomSpacing),

            quickActionsView.topAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.topAnchor),
            quickActionsView.leadingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.leadingAnchor),
            quickActionsView.trailingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.trailingAnchor),
            quickActionsView.bottomAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.bottomAnchor),
            quickActionsView.widthAnchor.constraint(equalTo: quickActionsScrollView.frameLayoutGuide.widthAnchor),
            fitContent,
        ]
    }

    func embedBasicNativeInputViewController() {
        addChild(basicNativeInputViewController)
        basicNativeInputViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(basicNativeInputViewController.view)
        basicNativeInputViewController.didMove(toParent: self)
    }

    func configureBasicNativeInput() {
        basicNativeInputViewController.delegate = self
        basicNativeInputViewController.placeholder = UserText.searchInputFieldPlaceholderDuckAI
    }

    func configureQuickActions() {
        quickActionsView.onActionSelected = { [weak self] action in
            self?.didSelectStartAction(action)
        }
    }

    func didSelectStartAction(_ action: ContextualSheetAction) {
        switch action {
        case .quickAction(let quickAction):
            delegate?.contextualInputViewController(self, didSelectQuickAction: quickAction)
        case .suggestion(let suggestion):
            delegate?.contextualInputViewController(self, didSelectSuggestion: suggestion)
        }
    }

    func configureWelcomeLabel() {
        welcomeLabel.isHidden = !showsWelcomeMessage

        let font = UIFont(name: "DuckSansDisplay-Medium", size: 25) ?? UIFont.daxTitle2()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(designSystemColor: .textPrimary),
            .paragraphStyle: paragraphStyle
        ]

        let shieldImage = DesignSystemImages.Color.Size32.shieldUtility
        let iconAttachment = NSTextAttachment()
        iconAttachment.image = shieldImage
        let iconVerticalOffset = (font.capHeight - shieldImage.size.height) / 2
        iconAttachment.bounds = CGRect(x: 0, y: iconVerticalOffset, width: shieldImage.size.width, height: shieldImage.size.height)
        let iconString = NSAttributedString(attachment: iconAttachment)

        let placeholder = "%@"
        let fullText = UserText.aiChatWelcomeMessage
        let mutableText = NSMutableAttributedString(string: fullText, attributes: defaultAttributes)

        if let placeholderRange = fullText.range(of: placeholder) {
            let nsRange = NSRange(placeholderRange, in: fullText)
            mutableText.replaceCharacters(in: nsRange, with: iconString)
        }

        welcomeLabel.attributedText = mutableText
    }

    func updateWelcomeLabelCentering() {
        let scrollViewTop = quickActionsScrollView.frame.minY
        guard scrollViewTop > 0 else { return }
        welcomeCenterYConstraint?.constant = scrollViewTop / 2
    }

    func scrollQuickActionsToBottom() {
        view.layoutIfNeeded()
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, quickActionsScrollView.contentSize.height - quickActionsScrollView.bounds.height)
        )
        quickActionsScrollView.setContentOffset(bottomOffset, animated: false)
    }

    func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    /// Going to the background closes the input for measurement; one still on screen on return counts as a new opening.
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        inputOutcomeMeasurement.inputClosed()
    }

    @objc private func appWillEnterForeground() {
        startInputOutcomeMeasurement()
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        isKeyboardCoveringColumn = keyboardOverlap(from: notification) >= Constants.floatingKeyboardOverlap
        let floats = !isAwaitingSubmittedChat
            && viewIfLoaded?.window != nil
            && isKeyboardCoveringColumn
        let animation = KeyboardAdaptationAnimation(notification)
        guard floats != isFloatingSuggestions else {
            bottomInset = -Constants.keyboardSpacing
            if floats, let keyboardTop = keyboardTopInColumnHost(from: notification) {
                floatingSuggestionsView.moveAbove(keyboardTop: keyboardTop, animation: (animation.duration, animation.options))
            }
            return
        }
        setFloatingSuggestions(floats, animation: animation, keyboardTop: keyboardTopInColumnHost(from: notification))
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        isKeyboardCoveringColumn = false
        guard isFloatingSuggestions else {
            bottomInset = bottomPaddingForOrientation()
            return
        }
        setFloatingSuggestions(false, animation: KeyboardAdaptationAnimation(notification), keyboardIsHiding: true)
    }

    /// A pass later: a keyboard on its way up can have the column laid out for it before its notification arrives here.
    func recordRestingStartActionFramesAfterThisPass() {
        guard !isRestingStartActionFramesRecordPending else { return }
        isRestingStartActionFramesRecordPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRestingStartActionFramesRecordPending = false
            guard !isFloatingSuggestions, !isKeyboardCoveringColumn else { return }
            restingStartActionFrames = quickActionsView.chipViews.map { $0.convert($0.bounds, to: self.view) }
        }
    }

    /// Where the keyboard's top edge lands, in the coordinate space the floating suggestions are placed in.
    func keyboardTopInColumnHost(from notification: Notification) -> CGFloat? {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let host = floatingSuggestionsColumn()?.superview,
              let screen = view.window?.windowScene?.screen else { return nil }
        return host.convert(endFrame, from: screen.coordinateSpace).minY
    }

    /// Measured against the column, which keeps its frame while the input above the keyboard moves.
    func keyboardOverlap(from notification: Notification) -> CGFloat {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let column = floatingSuggestionsColumn(),
              let screen = view.window?.windowScene?.screen else { return 0 }
        let keyboardFrame = column.convert(endFrame, from: screen.coordinateSpace)
        return column.bounds.intersection(keyboardFrame).height
    }

    /// Runs alongside the keyboard, so the suggestions slide out of the column as it rises and back as it falls.
    func setFloatingSuggestions(_ floats: Bool,
                                animation: KeyboardAdaptationAnimation?,
                                keyboardTop: CGFloat? = nil,
                                keyboardIsHiding: Bool = false,
                                animatesFloatingSuggestions: Bool = true,
                                returnsToColumn: Bool = true) {
        isFloatingSuggestions = floats
        if floats, let column = floatingSuggestionsColumn(), let host = column.superview {
            let isColumnListShowing = quickActionsScrollView.alpha > 0 && quickActionsView.alpha > 0
            let sourceFrames = isColumnListShowing ? restingStartActionFrames.map { view.convert($0, to: host) } : []
            floatingSuggestionsView.show(beside: column,
                                         keyboardTop: keyboardTop ?? host.bounds.maxY,
                                         from: sourceFrames)
            isLandingFloatingSuggestions = false
            // The floating chips take over in place, so the column's own fade would show each one twice.
            // Outside the keyboard's animation, which this notification arrives inside.
            UIView.performWithoutAnimation { updateStartActionsVisibility() }
        } else if floatingSuggestionsView.isShown {
            let host = floatingSuggestionsColumn()?.superview
            let isColumnListReturning = returnsToColumn && inputText.isEmpty
            // The column is already laid out for the keyboard going down, so its chips' frames are where they will rest.
            view.layoutIfNeeded()
            let targetFrames = isColumnListReturning && animatesFloatingSuggestions
                ? host.map { host in quickActionsView.chipViews.map { $0.convert($0.bounds, to: host) } } ?? []
                : []
            isLandingFloatingSuggestions = !targetFrames.isEmpty
            floatingSuggestionsView.hide(animated: animatesFloatingSuggestions, to: targetFrames) { [weak self] in
                guard let self, isLandingFloatingSuggestions else { return }
                isLandingFloatingSuggestions = false
                updateStartActionsVisibility()
            }
        }
        let changes = { [self] in
            bottomInset = keyboardIsHiding ? bottomPaddingForOrientation() : -Constants.keyboardSpacing
            updateStartActionsVisibility()
        }
        if let animation {
            UIView.animate(withDuration: animation.duration, delay: 0, options: animation.options, animations: changes)
        } else {
            changes()
        }
    }

    func updateStartActionsVisibilityForText() {
        guard isFloatingSuggestions else { return }
        UIView.animate(withDuration: 0.2) {
            self.updateStartActionsVisibility()
        }
    }

    /// While the suggestions float, they step aside once the user types a prompt of their own,
    /// and the column's own list stays empty.
    func updateStartActionsVisibility() {
        let hidesForText = isFloatingSuggestions && !inputText.isEmpty
        let isColumnListHidden = isFloatingSuggestions || isLandingFloatingSuggestions || isAwaitingSubmittedChat
        quickActionsScrollView.alpha = isColumnListHidden ? 0 : 1
        quickActionsScrollView.isUserInteractionEnabled = !isColumnListHidden
        // Only while floating: chips flying home with a prompt typed must not reappear on the way.
        if isFloatingSuggestions {
            floatingSuggestionsView.isSteppedAside = hidesForText
        }
    }

    /// When the list has to scroll, the chips nearest the input stay in view.
    func keepNearestStartActionsVisible() {
        let height = quickActionsScrollView.bounds.height
        defer { lastStartActionsHeight = height }
        guard height != lastStartActionsHeight else { return }
        let maxOffset = max(0, quickActionsScrollView.contentSize.height - height)
        quickActionsScrollView.contentOffset = CGPoint(x: 0, y: maxOffset)
    }

    /// Fades whichever edge has chips scrolled out past it, so a cut-off chip reads as more to scroll to.
    func updateStartActionsEdgeFade() {
        let scrollView = quickActionsScrollView
        let length = scrollView.bounds.height
        let contentLength = scrollView.contentSize.height
        let offset = scrollView.contentOffset.y
        guard length > 0, contentLength > length + 1 else {
            scrollView.layer.mask = nil
            return
        }

        let fade = min(Constants.startActionsEdgeFadeLength / length, 0.5)
        let opaque = UIColor.black.cgColor
        let clear = UIColor.black.withAlphaComponent(0).cgColor
        let mask = startActionsEdgeFadeMask
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        mask.colors = [offset > 1 ? clear : opaque, opaque, opaque, offset + length < contentLength - 1 ? clear : opaque]
        mask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        mask.frame = scrollView.bounds
        CATransaction.commit()
        scrollView.layer.mask = mask
    }

    func updateBottomPaddingForOrientation() {
        bottomInset = bottomPaddingForOrientation()
    }

    func bottomPaddingForOrientation() -> CGFloat {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return 0 }
        return -Constants.iPadBottomPadding
    }
}

// MARK: - AIChatBasicNativeInputViewControllerDelegate

extension AIChatContextualInputViewController: AIChatBasicNativeInputViewControllerDelegate {

    func basicNativeInputViewController(_ viewController: AIChatBasicNativeInputViewController, didSubmitPrompt prompt: String) {
        delegate?.contextualInputViewController(self, didSubmitPrompt: prompt)
    }

    func basicNativeInputViewControllerDidTapVoice(_ viewController: AIChatBasicNativeInputViewController) {
        delegate?.contextualInputViewControllerDidTapVoice(self)
    }

    func basicNativeInputViewControllerDidRemoveContextChip(_ viewController: AIChatBasicNativeInputViewController) {
        delegate?.contextualInputViewControllerDidRemoveContextChip(self)
    }

    func basicNativeInputViewController(_ viewController: AIChatBasicNativeInputViewController, didChangeText text: String) {
        scrollQuickActionsToBottom()
        updateStartActionsVisibilityForText()
    }
}

// MARK: - Start Actions Scroll View

/// Reports each layout pass, the first point where its content size is current.
private final class StartActionsScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

// MARK: - Keyboard Animation

private struct KeyboardAdaptationAnimation {
    let duration: TimeInterval
    let options: UIView.AnimationOptions

    init(_ notification: Notification) {
        let userInfo = notification.userInfo
        duration = userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        options = UIView.AnimationOptions(rawValue: curve << 16)
    }
}
