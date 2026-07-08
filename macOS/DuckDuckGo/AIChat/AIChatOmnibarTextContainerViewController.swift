//
//  AIChatOmnibarTextContainerViewController.swift
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

import Cocoa
import Combine
import AIChat
import PixelKit
import PrivacyConfig

final class AIChatOmnibarTextContainerViewController: NSViewController, ThemeUpdateListening, NSTextViewDelegate {

    private enum Constants {
        static let bottomPadding: CGFloat = 34.0
        static let minimumPanelHeight: CGFloat = 60
        static let maximumPanelHeight: CGFloat = 512.0
        static let dividerLeadingOffset: CGFloat = -9.0
        static let dividerTrailingOffset: CGFloat = 77.0
        static let dividerTopOffset: CGFloat = -10.0
        static let placeholderLeadingOffset: CGFloat = 10
        static let placeholderLegacyLeadingOffset: CGFloat = 9
    }

    private let backgroundView = MouseBlockingBackgroundView()
    private let containerView = NSView()
    private let scrollView = NSScrollView()
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()
    private let textView: FocusableTextView
    private let placeholderLabel = ClickThroughLabel(labelWithString: "")
    private let dividerView = ColorView(frame: .zero)
    private let omnibarController: AIChatOmnibarController
    /// Coordinator for the `@`-mention tab picker. `nil` until the first detected token, so
    /// the panel and view controller don't allocate while the user just types in the omnibar
    /// without ever triggering `@`. Use `ensureMentionPickerCoordinator()` at the present
    /// site to lazy-init; all dismiss / read-state call sites use optional chaining and
    /// no-op safely while still nil.
    private var mentionPickerCoordinator: AIChatMentionPickerCoordinator?

    /// Lazy-init the coordinator on first use (the `presentIfNeeded` path). Other paths
    /// (dismiss, isPresented, canHandleKeyCommands) should stay on optional chaining so
    /// they don't force allocation when the user never typed `@`.
    private func ensureMentionPickerCoordinator() -> AIChatMentionPickerCoordinator {
        if let mentionPickerCoordinator { return mentionPickerCoordinator }
        let coordinator = AIChatMentionPickerCoordinator(omnibarController: omnibarController)
        mentionPickerCoordinator = coordinator
        return coordinator
    }
    private var cancellables = Set<AnyCancellable>()
    /// When true, the text view is being updated programmatically (text or selection) and any
    /// resulting `textViewDidChangeSelection` callback must not overwrite the persisted caret
    /// position — otherwise e.g. a tab-switch cleanup that clears `currentText` would also wipe
    /// the saved selection with `(0, 0)` before we get a chance to restore it.
    private var isUpdatingProgrammatically = false

    private let featureFlagger: FeatureFlagger
    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    weak var customToggleControl: NSControl?
    weak var containerViewController: AIChatOmnibarContainerViewController? {
        didSet { wireTabCycle() }
    }
    var heightDidChange: ((CGFloat) -> Void)?
    /// Fires when the prompt text view becomes first responder.
    /// Used by the orchestrating layer to re-focus into duck.ai mode when the user clicks the prompt while unfocused.
    var onTextViewDidBecomeFirstResponder: (() -> Void)?

    init(omnibarController: AIChatOmnibarController, themeManager: ThemeManaging, featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.omnibarController = omnibarController
        self.themeManager = themeManager
        self.featureFlagger = featureFlagger

        textStorage.addLayoutManager(layoutManager)
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        textView = FocusableTextView(frame: .zero, textContainer: textContainer)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = MouseOverView()
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        view.setAccessibilityIdentifier("AIChatOmnibarTextContainerViewController.view")
        view.setAccessibilityElement(true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTextViewDelegate()
        subscribeToThemeChanges()
        applyThemeStyle()

        scrollView.documentView = textView
        textView.navigationDelegate = self
        textView.registerForImageDrop()
        textView.onDidBecomeFirstResponder = { [weak self] in
            self?.onTextViewDidBecomeFirstResponder?()
        }
    }

    /// Whether the prompt editor is currently the window's first responder.
    var isTextViewFirstResponder: Bool {
        view.window?.firstResponder === textView
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        subscribeToViewAppearanceChanges()
    }

    private func subscribeToViewAppearanceChanges() {
        appearanceCancellable = view.publisher(for: \.effectiveAppearance)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyThemeStyle()
            }
    }

    private func setupUI() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.masksToBounds = false
        view.addSubview(backgroundView)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = false
        backgroundView.addSubview(containerView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.horizontalScroller?.alphaValue = 0

        containerView.addSubview(scrollView)

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.backgroundColor = NSColor.separatorColor
        dividerView.isHidden = true
        view.addSubview(dividerView)

        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 5, height: 9) /// Match address bar text positioning
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.usesRuler = false
        textView.usesFontPanel = false
        textView.delegate = self
        textView.setAccessibilityIdentifier("AIChatOmnibarTextContainerViewController.textView")
        textView.setAccessibilityElement(true)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.stringValue = UserText.aiChatOmnibarPlaceholder
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.hitTestForwardingTarget = textView
        containerView.addSubview(placeholderLabel)

        let placeholderLeadingConstant = themeManager.isAppRebranded ? Constants.placeholderLeadingOffset : Constants.placeholderLegacyLeadingOffset

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 1.0),
            containerView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Constants.bottomPadding),

            // Divider overflows beyond view bounds
            dividerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.dividerLeadingOffset),
            dividerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: Constants.dividerTrailingOffset),
            dividerView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: Constants.dividerTopOffset),
            dividerView.heightAnchor.constraint(equalToConstant: 1),

            placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: placeholderLeadingConstant),
            placeholderLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 9),
        ])
    }

    func applyThemeStyle(theme: ThemeStyleProviding) {
        let colorsProvider = theme.colorsProvider
        let addressBarStyleProvider = theme.addressBarStyleProvider

        backgroundView.backgroundColor = .clear

        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = NSColor.textColor
        textView.font = .systemFont(ofSize: addressBarStyleProvider.defaultAddressBarFontSize, weight: .regular)

        textView.insertionPointColor = colorsProvider.addressBarTextFieldColor

        placeholderLabel.textColor = colorsProvider.textSecondaryColor
        placeholderLabel.font = .systemFont(ofSize: addressBarStyleProvider.defaultAddressBarFontSize, weight: .regular)

        dividerView.backgroundColor = NSColor.separatorColor
    }

    private func setupTextViewDelegate() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )

        omnibarController.$currentText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newText in
                guard let self = self else { return }
                if self.textView.string != newText {
                    self.isUpdatingProgrammatically = true
                    self.textView.string = newText
                    if self.view.window?.firstResponder == self.textView {
                        let textLength = newText.count
                        self.textView.selectedRange = NSRange(location: textLength, length: 0)
                    }
                    self.isUpdatingProgrammatically = false
                    /// Update panel height when text changes programmatically (e.g., from paste)
                    self.updatePanelHeight()
                }
                self.updatePlaceholderVisibility()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            omnibarController.$activeToolMode,
            omnibarController.$hasImageAttachments
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] toolMode, hasAttachments in
            switch toolMode {
            case .imageGeneration where hasAttachments:
                self?.placeholderLabel.stringValue = UserText.aiChatImageGenWithAttachmentPlaceholder
            case .imageGeneration:
                self?.placeholderLabel.stringValue = UserText.aiChatImageGenPlaceholder
            default:
                self?.placeholderLabel.stringValue = UserText.aiChatOmnibarPlaceholder
            }
        }
        .store(in: &cancellables)
    }

    @objc func textDidChange(_ notification: Notification) {
        omnibarController.updateText(textView.string)
        omnibarController.updateSelection(textView.selectedRange)
        let currentScrollPosition = scrollView.documentVisibleRect.origin
        updatePanelHeight()
        updatePlaceholderVisibility()
        updateMentionTokenDetection()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.textView.scroll(currentScrollPosition)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        /// Persist the caret / selection to the current tab's shared state so the same position is
        /// restored when the panel is re-activated (tab switch, refocus, etc.).
        /// Skip programmatic updates — otherwise clearing `textView.string` via the `$currentText`
        /// sink (triggered by cleanup on tab switch) would overwrite the saved selection with `(0, 0)`.
        guard !isUpdatingProgrammatically else { return }
        omnibarController.updateSelection(textView.selectedRange)
        // Caret movement (arrow keys, mouse click) can move the caret in or out of an @-token —
        // re-check on selection changes too, not only on text edits.
        updateMentionTokenDetection()
    }

    /// Fired by `NSTextView` whenever it resigns first-responder status — covers
    /// click-outside, Cmd-Tab to another app, etc. The picker should not stay floating
    /// above an unfocused input.
    ///
    /// Esc is intercepted *before* it gets here (see `dismissMentionPickerIfPresented` —
    /// the address bar's `escapeKeyDown` consults that hook and short-circuits when the
    /// picker is open so the omnibar's focus is preserved).
    func textDidEndEditing(_ notification: Notification) {
        // `?.` — skip the lazy allocation when the user never typed `@`. The coordinator
        // would no-op anyway, but avoiding the alloc keeps the omnibar's idle path cheap.
        mentionPickerCoordinator?.dismiss(reason: .textEndedEditing)
    }

    /// Called by `AddressBarViewController.escapeKeyDown()` (via the wiring set up in
    /// `MainViewController`) when the user presses Esc. Returns `true` when the picker was
    /// presented and got dismissed — the address bar uses that to short-circuit its own
    /// focus-resign behavior so the user can keep typing in the omnibar.
    func dismissMentionPickerIfPresented() -> Bool {
        guard let coordinator = mentionPickerCoordinator, coordinator.isPresented else { return false }
        coordinator.dismiss(reason: .userEscape)
        return true
    }

    /// Detects whether the caret is currently inside an `@`-mention token in the omnibar input
    /// and presents (or dismisses) the mention picker panel accordingly. The detector itself
    /// is in `AIChatMentionTokenDetector`; this method only does the panel-lifecycle glue.
    private func updateMentionTokenDetection() {
        // Gate on the same `isOmnibarTabPickerEnabled` feature flag the "Add Page Content"
        // submenu uses. Without this, a user typing `@` in the omnibar would see the picker
        // regardless of the `aiChatOmnibarAttachMoreTabs` rollout state. Dismissing any
        // already-presented picker too, so a remote flag flip-off while the panel is on
        // screen tears it down on the next text edit / selection change. `?.` so the
        // dismiss-only paths below don't lazy-allocate the coordinator when it was never
        // needed (user typing without `@`, flag off, etc.).
        guard omnibarController.isOmnibarTabPickerEnabled else {
            mentionPickerCoordinator?.dismiss(reason: .featureFlagOff)
            return
        }
        let selection = textView.selectedRange
        // Use the selection's upper bound when the user has selected text, so the splice
        // sweeps the full `@token` (matching the "Enter collapses selection" intuition).
        // Collapsed selections degenerate to `location == upperBound`.
        let caret = selection.length > 0 ? selection.upperBound : selection.location
        guard let token = AIChatMentionTokenDetector.token(in: textView.string, caret: caret) else {
            mentionPickerCoordinator?.dismiss(reason: .tokenGone)
            return
        }
        guard let window = view.window else {
            // No window yet (e.g. VC is being attached) — defer; the next text change will
            // re-evaluate once the view is attached.
            return
        }
        // Present path: this is the one site that needs the coordinator instance, so
        // lazy-init here.
        ensureMentionPickerCoordinator().presentIfNeeded(for: token, anchoredTo: textView, in: window)
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    private func updatePanelHeight() {
        let desiredHeight = calculateDesiredPanelHeight()
        heightDidChange?(desiredHeight)
    }

    func calculateDesiredPanelHeight() -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return Constants.minimumPanelHeight
        }

        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let textInsets = textView.textContainerInset
        let bottomSpacing: CGFloat = Constants.bottomPadding
        let totalHeight = usedRect.height + textInsets.height + bottomSpacing

        return max(Constants.minimumPanelHeight, min(totalHeight, Constants.maximumPanelHeight))
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Mention picker takes first crack at arrow up/down/Enter/Esc when it's on screen.
        // The arrow / Enter cases need a real (non-empty-state) selection, so they're gated
        // on `canHandleKeyCommands`; Esc dismisses regardless so the user can keep typing
        // without the panel covering content. The picker only matters when it has already
        // been instantiated and presented — bind once via `if let` so we don't lazy-allocate
        // the coordinator on every keystroke.
        if let coordinator = mentionPickerCoordinator, coordinator.isPresented {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                coordinator.dismiss(reason: .userEscape)
                return true
            case #selector(NSResponder.moveDown(_:)) where coordinator.canHandleKeyCommands:
                coordinator.moveHighlightDown()
                return true
            case #selector(NSResponder.moveUp(_:)) where coordinator.canHandleKeyCommands:
                coordinator.moveHighlightUp()
                return true
            case #selector(insertNewline(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)):
                if coordinator.canHandleKeyCommands, coordinator.acceptHighlighted() {
                    return true
                }
                // No real selection — fall through to the normal Enter path below.
            default:
                break
            }
        }

        if commandSelector == #selector(insertNewline(_:)) || commandSelector == #selector(insertNewlineIgnoringFieldEditor(_:)) {
            guard let event = NSApp.currentEvent else { return false }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if modifiers.contains(.option) || modifiers.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }

            // Voice handoff requires an explicit click on the voice button. Enter on an empty
            // input must not implicitly start a voice session — it stays a no-op via `submit()`,
            // mirroring the legacy disabled-submit behavior.
            omnibarController.submit()
            return true
        } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if let customToggleControl = customToggleControl,
               !customToggleControl.isHidden,
               customToggleControl.isEnabled {
                view.window?.makeFirstResponder(customToggleControl)
                return true
            }
            return false

        }

        return false
    }

    func startEventMonitoring() {
        backgroundView.startListening()
    }

    func stopEventMonitoring() {
        backgroundView.stopListening()
    }

    /// Sets the height from the bottom that should pass events through to views behind.
    /// Used to allow clicks to reach suggestions in the container view.
    func setPassthroughBottomHeight(_ height: CGFloat) {
        backgroundView.passthroughBottomHeight = height
    }

    func focusTextView() {
        view.window?.makeFirstResponder(textView)
    }

    func focusTextViewWithCursorAtEnd() {
        focusTextView()
        moveCursorToEnd()
    }

    /// Focuses the text view and restores the caret to the position persisted for the current tab,
    /// falling back to the end of the prompt when no position has been saved yet or when the saved
    /// location is past the current text length.
    func focusTextViewRestoringCursorPosition() {
        focusTextView()
        isUpdatingProgrammatically = true
        /// `saved.location` is a UTF-16 offset (it came from an `NSRange`), so compare it against the
        /// UTF-16 length of the string rather than `String.count` (grapheme-cluster count). For prompts
        /// containing emoji or other non-BMP characters the two differ and valid saved positions would
        /// otherwise fail the bounds check and fall through to `moveCursorToEnd`.
        let utf16Length = (textView.string as NSString).length
        if let saved = omnibarController.currentSelectionRange,
           saved.location <= utf16Length {
            let clampedLength = min(saved.length, max(0, utf16Length - saved.location))
            textView.selectedRange = NSRange(location: saved.location, length: clampedLength)
        } else {
            moveCursorToEnd()
        }
        isUpdatingProgrammatically = false

        // Re-evaluate `@`-mention detection now that focus + caret have been restored. Without
        // this, typing `@` in search mode and then toggling to Duck.ai leaves the text in place
        // but never fires `textDidChange`/`textViewDidChangeSelection` (the text update is
        // programmatic, the selection update is suppressed via `isUpdatingProgrammatically`),
        // so the picker would otherwise never open for a pre-existing `@` token.
        updateMentionTokenDetection()
    }

    /// Forces the text view's string to match `omnibarController.currentText` synchronously.
    /// The normal `$currentText` → `textView.string` path is async (receive(on: .main)), so typing in search
    /// mode and immediately toggling to Duck.ai can show the prompt filling in after the panel is already visible.
    /// Call this at activation to snap the text in place without the visible fill-in.
    func syncTextViewToCurrentText() {
        let newText = omnibarController.currentText
        if textView.string != newText {
            isUpdatingProgrammatically = true
            textView.string = newText
            isUpdatingProgrammatically = false
            updatePlaceholderVisibility()
            updatePanelHeight()
        }
    }

    /// Moves the caret to the end of the prompt text without changing first responder.
    /// Uses the UTF-16 length of the string, not `String.count` (grapheme-cluster count),
    /// because `selectedRange` is an `NSRange` measured in UTF-16. For prompts containing
    /// emoji or other non-BMP characters the two values differ and the previous version
    /// would land the caret before the real end of the text.
    func moveCursorToEnd() {
        let textLength = (textView.string as NSString).length
        textView.selectedRange = NSRange(location: textLength, length: 0)
    }

    // MARK: - Tab Navigation

    /// Called by the owner when the toggle receives a Tab press in AI Chat mode.
    func handleToggleTabPressed() {
        guard let containerVC = containerViewController else {
            focusTextViewWithCursorAtEnd()
            return
        }
        if containerVC.firstAvailableToolButtonForFocus() != nil {
            containerVC.makeFirstAvailableToolButtonFirstResponder()
        } else if containerVC.isModelPickerButtonAvailableForFocus {
            containerVC.makeModelPickerButtonFirstResponder()
        } else {
            focusTextViewWithCursorAtEnd()
        }
    }

    private func wireTabCycle() {
        guard let containerVC = containerViewController else { return }

        containerVC.onToolButtonTabPressed = { [weak self] in
            self?.focusTextViewWithCursorAtEnd()
        }
    }

    func insertNewline() {
        textView.insertNewlineIgnoringFieldEditor(nil)
    }

    func insertNewlineIfHasContent(addressBarText: String) {
        guard !addressBarText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        insertNewline()
    }

    func updateScrollingBehavior(maxHeight: CGFloat) {
        let desiredHeight = calculateDesiredPanelHeight()
        let effectiveMaxHeight = min(maxHeight, Constants.maximumPanelHeight)
        let shouldScroll = desiredHeight >= effectiveMaxHeight

        scrollView.hasVerticalScroller = shouldScroll
        dividerView.isHidden = !shouldScroll

        if shouldScroll {
            textView.scrollToEndOfDocument(nil)
        }
    }
}

// MARK: - FocusableTextViewNavigationDelegate
extension AIChatOmnibarTextContainerViewController: FocusableTextViewNavigationDelegate {

    func textViewDidRequestMoveToSuggestions() -> Bool {
        let viewModel = omnibarController.suggestionsViewModel

        // If already at last item (including the virtual "view all" row), clear selection (cycle back to text field)
        let lastIndex = viewModel.filteredSuggestions.count - 1 + (viewModel.showViewAllChats ? 1 : 0)
        if let currentIndex = viewModel.selectedIndex, currentIndex >= lastIndex {
            viewModel.clearSelection(keepMouseSuppressed: true)
            return true
        }

        // Try to select next suggestion
        return viewModel.selectNext()
    }

    func textViewDidRequestMoveFromSuggestions() -> Bool {
        let viewModel = omnibarController.suggestionsViewModel
        // selectPrevious handles both cases:
        // - No selection: selects last item
        // - Has selection: moves up or clears selection at top
        return viewModel.selectPrevious()
    }

    func isSuggestionSelected() -> Bool {
        omnibarController.suggestionsViewModel.selectedIndex != nil
    }

    func textViewDidRequestSelectCurrentSuggestion() -> Bool {
        if omnibarController.suggestionsViewModel.isViewAllChatsSelected {
            return omnibarController.submitSelectedSuggestion()
        }

        guard let suggestion = omnibarController.suggestionsViewModel.selectedSuggestion else {
            return false
        }
        let pixel: AIChatPixel = suggestion.isPinned ? .aiChatRecentChatSelectedPinnedKeyboard : .aiChatRecentChatSelectedKeyboard
        PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
        omnibarController.delegate?.aiChatOmnibarController(omnibarController, didSelectSuggestion: suggestion)
        return true
    }

    func textViewDidReceiveImageDrop(_ fileURLs: [URL]) -> Bool {
        guard let containerVC = containerViewController else { return false }
        guard omnibarController.isOmnibarToolsEnabled else { return false }
        let canAttach = omnibarController.isImageGenerationMode || omnibarController.selectedModelSupportsImageUpload
        guard canAttach else { return false }
        var accepted = false
        for url in fileURLs where containerVC.addImageAttachmentFromDrop(url) {
            accepted = true
        }
        return accepted
    }
}

/// Delegate protocol for handling navigation events from FocusableTextView
protocol FocusableTextViewNavigationDelegate: AnyObject {
    /// Called when user presses down arrow on the last line
    /// - Returns: `true` if navigation was handled (moved to suggestions), `false` otherwise
    func textViewDidRequestMoveToSuggestions() -> Bool
    /// Called when user presses up arrow on the first line (when suggestions are selected)
    /// - Returns: `true` if navigation was handled, `false` otherwise
    func textViewDidRequestMoveFromSuggestions() -> Bool
    /// Whether a suggestion is currently selected in the suggestions list.
    func isSuggestionSelected() -> Bool
    /// Called when user presses Enter while a suggestion is selected
    /// - Returns: `true` if a suggestion was selected, `false` otherwise
    func textViewDidRequestSelectCurrentSuggestion() -> Bool
    /// Called when the user drops image files onto the text view
    /// - Returns: `true` if any images were accepted, `false` otherwise
    func textViewDidReceiveImageDrop(_ fileURLs: [URL]) -> Bool
}

/// NSTextField label that forwards mouse hits to a configured target view.
/// Used for the prompt placeholder: clicks on the placeholder area hit-test to the text view so the prompt takes focus,
/// rather than falling through the empty scroll-view area to the address bar behind (which would switch to search mode).
private final class ClickThroughLabel: NSTextField {
    weak var hitTestForwardingTarget: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return hitTestForwardingTarget ?? nil
    }
}

/// Custom NSTextView that ensures it can always accept focus when clicked
private final class FocusableTextView: NSTextView {

    weak var navigationDelegate: FocusableTextViewNavigationDelegate?

    /// Fires when the text view transitions from not-first-responder to first-responder (gaining focus).
    var onDidBecomeFirstResponder: (() -> Void)?

    private var wasFirstResponder: Bool = false

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome && !wasFirstResponder {
            wasFirstResponder = true
            onDidBecomeFirstResponder?()
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            wasFirstResponder = false
        }
        return didResign
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"]

    func registerForImageDrop() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !Self.imageFileURLs(from: sender).isEmpty {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !Self.imageFileURLs(from: sender).isEmpty {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let imageURLs = Self.imageFileURLs(from: sender)
        if !imageURLs.isEmpty,
           navigationDelegate?.textViewDidReceiveImageDrop(imageURLs) == true {
            return true
        }
        return super.performDragOperation(sender)
    }

    private static func imageFileURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
        guard let urls = draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else {
            return []
        }
        return urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder != self {
            /// Refocus click: make this the first responder so the refocus flow (via `becomeFirstResponder` →
            /// `onDidBecomeFirstResponder` callback → `focusTextViewRestoringCursorPosition`) can restore the
            /// caret to the position saved for the current tab. Skip `super.mouseDown` so NSTextView doesn't
            /// override our restored selection with a click-location caret; a subsequent click with the text
            /// view already first responder positions the caret normally.
            window?.makeFirstResponder(self)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Handle Enter key when a suggestion might be selected
        if event.keyCode == 36 { // Return/Enter key
            if navigationDelegate?.textViewDidRequestSelectCurrentSuggestion() == true {
                return
            }
        }
        super.keyDown(with: event)
    }

    override func moveDown(_ sender: Any?) {
        let suggestionSelected = navigationDelegate?.isSuggestionSelected() ?? false
        if suggestionSelected || isCursorOnLastLine() {
            if navigationDelegate?.textViewDidRequestMoveToSuggestions() == true {
                return
            }
        }
        super.moveDown(sender)
    }

    override func moveUp(_ sender: Any?) {
        let suggestionSelected = navigationDelegate?.isSuggestionSelected() ?? false
        if suggestionSelected || isCursorOnFirstLine() {
            if navigationDelegate?.textViewDidRequestMoveFromSuggestions() == true {
                return
            }
        }
        super.moveUp(sender)
    }

    /// Checks if the cursor is on the last line of the text view
    private func isCursorOnLastLine() -> Bool {
        guard let layoutManager = layoutManager,
              textContainer != nil else {
            return true
        }

        let selectedRange = selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)

        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &lineRange)

        let lastGlyphIndex = layoutManager.numberOfGlyphs > 0 ? layoutManager.numberOfGlyphs - 1 : 0
        var lastLineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: &lastLineRange)

        return NSMaxRange(lineRange) >= NSMaxRange(lastLineRange)
    }

    /// Checks if the cursor is on the first line of the text view
    private func isCursorOnFirstLine() -> Bool {
        guard let layoutManager = layoutManager else {
            return true
        }

        let selectedRange = selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)

        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &lineRange)

        return lineRange.location == 0
    }
}
