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

final class AIChatOmnibarTextContainerViewController: NSViewController, ThemeUpdateListening, NSTextViewDelegate {

    private let backgroundView = MouseBlockingBackgroundView()
    private let containerView = NSView()
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let omnibarController: AIChatOmnibarController
    private let sharedTextState: AddressBarSharedTextState
    private var cancellables = Set<AnyCancellable>()
    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?

    init(omnibarController: AIChatOmnibarController, sharedTextState: AddressBarSharedTextState, themeManager: ThemeManaging) {
        self.omnibarController = omnibarController
        self.sharedTextState = sharedTextState
        self.themeManager = themeManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = MouseOverView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTextViewDelegate()
        subscribeToThemeChanges()
        applyThemeStyle()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        scrollView.documentView = textView
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
        view.addSubview(backgroundView)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(containerView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        containerView.addSubview(scrollView)

        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 5, height: 9) /// Match address bar text positioning
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.usesRuler = false
        textView.usesFontPanel = false
        textView.delegate = self

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }

    func applyThemeStyle(theme: ThemeStyleProviding) {
        let colorsProvider = theme.colorsProvider
        let addressBarStyleProvider = theme.addressBarStyleProvider

        backgroundView.backgroundColor = colorsProvider.activeAddressBarBackgroundColor

        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = colorsProvider.addressBarTextFieldColor
        textView.font = .systemFont(ofSize: addressBarStyleProvider.defaultAddressBarFontSize, weight: .regular)

        textView.insertionPointColor = colorsProvider.addressBarTextFieldColor
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
                    let textLength = newText.count
                    self.textView.selectedRange = NSRange(location: textLength, length: 0)
                }
            }
            .store(in: &cancellables)
    }

    @objc func textDidChange(_ notification: Notification) {
        omnibarController.updateText(textView.string)
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
        }

        return false
    }

    func startEventMonitoring() {
        backgroundView.startListening()
    }

    func cleanup() {
        backgroundView.stopListening()
    }

    func focusTextView() {
        view.window?.makeFirstResponder(textView)
    }
}
