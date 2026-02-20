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

final class AIChatOmnibarTextContainerViewController: NSViewController, ThemeUpdateListening, NSTextViewDelegate {

    private enum Constants {
        static let bottomPadding: CGFloat = 34.0
        static let minimumPanelHeight: CGFloat = 60
        static let maximumPanelHeight: CGFloat = 512.0
        static let dividerLeadingOffset: CGFloat = -9.0
        static let dividerTrailingOffset: CGFloat = 77.0
        static let dividerTopOffset: CGFloat = -10.0
    }

    private let backgroundView = MouseBlockingBackgroundView()
    private let containerView = NSView()
    private let scrollView = NSScrollView()
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()
    private let textView: FocusableTextView
    private let placeholderLabel = NSTextField(labelWithString: "")
    private let dividerView = ColorView(frame: .zero)
    private let omnibarController: AIChatOmnibarController
    private var cancellables = Set<AnyCancellable>()
    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    weak var customToggleControl: NSControl?
    var heightDidChange: ((CGFloat) -> Void)?

    init(omnibarController: AIChatOmnibarController, themeManager: ThemeManaging) {
        self.omnibarController = omnibarController
        self.themeManager = themeManager

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
        containerView.addSubview(placeholderLabel)

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

            placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 9),
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
                    self.textView.string = newText
                    if self.view.window?.firstResponder == self.textView {
                        let textLength = newText.count
                        self.textView.selectedRange = NSRange(location: textLength, length: 0)
                    }
                    /// Update panel height when text changes programmatically (e.g., from paste)
                    self.updatePanelHeight()
                }
                self.updatePlaceholderVisibility()
            }
            .store(in: &cancellables)
    }

    @objc func textDidChange(_ notification: Notification) {
        omnibarController.updateText(textView.string)
        let currentScrollPosition = scrollView.documentVisibleRect.origin
        updatePanelHeight()
        updatePlaceholderVisibility()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.textView.scroll(currentScrollPosition)
        }
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
        if commandSelector == #selector(insertNewline(_:)) || commandSelector == #selector(insertNewlineIgnoringFieldEditor(_:)) {
            guard let event = NSApp.currentEvent else { return false }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if modifiers.contains(.option) || modifiers.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }

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
        let textLength = textView.string.count
        textView.selectedRange = NSRange(location: textLength, length: 0)
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

        // If already at last suggestion, clear selection (cycle back to text field)
        if let currentIndex = viewModel.selectedIndex,
           currentIndex >= viewModel.filteredSuggestions.count - 1 {
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

    func textViewDidRequestSelectCurrentSuggestion() -> Bool {
        guard let suggestion = omnibarController.suggestionsViewModel.selectedSuggestion else {
            return false
        }
        let pixel: AIChatPixel = suggestion.isPinned ? .aiChatRecentChatSelectedPinnedKeyboard : .aiChatRecentChatSelectedKeyboard
        PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
        omnibarController.delegate?.aiChatOmnibarController(omnibarController, didSelectSuggestion: suggestion)
        return true
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
    /// Called when user presses Enter while a suggestion is selected
    /// - Returns: `true` if a suggestion was selected, `false` otherwise
    func textViewDidRequestSelectCurrentSuggestion() -> Bool
}

/// Custom NSTextView that ensures it can always accept focus when clicked
private final class FocusableTextView: NSTextView {

    weak var navigationDelegate: FocusableTextViewNavigationDelegate?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder != self {
            window?.makeFirstResponder(self)
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
        if isCursorOnLastLine() {
            if navigationDelegate?.textViewDidRequestMoveToSuggestions() == true {
                return
            }
        }
        super.moveDown(sender)
    }

    override func moveUp(_ sender: Any?) {
        // First check if we should navigate in suggestions
        if navigationDelegate?.textViewDidRequestMoveFromSuggestions() == true {
            return
        }
        super.moveUp(sender)
    }

    /// Checks if the cursor is on the last line of the text view
    private func isCursorOnLastLine() -> Bool {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
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
}
