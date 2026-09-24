//
//  CrashReportPromptViewController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import CrashReportingShared

@MainActor
final class CrashReportPromptViewController: NSViewController {

    private enum Constants {
        static let contentSize = CGSize(width: 550, height: 427)
        static let horizontalInset: CGFloat = 20
        static let descriptionWidth: CGFloat = 510
        static let textViewHeight: CGFloat = 261
        static let bottomInset: CGFloat = 20
        static let textViewBottomInset: CGFloat = 50
        static let textViewMaxWidth: CGFloat = 562
    }

    private let titleLabel = NSTextField(labelWithString: UserText.crashReportTitle)
    private let descriptionLabel = NSTextField(wrappingLabelWithString: UserText.crashReportDescription)
    private let textFieldTitle = NSTextField(labelWithString: UserText.crashReportTextFieldTitle)
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private lazy var sendButton = NSButton(title: UserText.crashReportSendButton, target: self, action: #selector(sendAction))
    private lazy var dontSendButton = NSButton(title: UserText.crashReportDontSendButton, target: self, action: #selector(dontSendAction))

    var userDidAnswerPrompt: ((CrashReportPromptPresenter.Response) -> Void)?

    var crashReport: CrashReportPresenting? {
        didSet {
            updateView()
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("\(type(of: self)): Bad initializer")
    }

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: Constants.contentSize))

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byClipping

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        descriptionLabel.isSelectable = false

        textFieldTitle.translatesAutoresizingMaskIntoConstraints = false
        textFieldTitle.lineBreakMode = .byClipping

        textView.isEditable = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.usesRuler = true
        textView.smartInsertDeleteEnabled = true
        textView.textColor = .secondaryLabelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .textColor
        textView.minSize = NSSize(width: 495, height: Constants.textViewHeight)
        textView.maxSize = NSSize(width: Constants.textViewMaxWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width, .height]

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = textView

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"

        dontSendButton.translatesAutoresizingMaskIntoConstraints = false
        dontSendButton.bezelStyle = .rounded

        view.addSubview(titleLabel)
        view.addSubview(descriptionLabel)
        view.addSubview(textFieldTitle)
        view.addSubview(scrollView)
        view.addSubview(sendButton)
        view.addSubview(dontSendButton)

        // The vertical chain is anchored at the bottom and grows upwards; the title label's top edge
        // is intentionally left free.
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            view.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: Constants.horizontalInset),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            view.trailingAnchor.constraint(equalTo: descriptionLabel.trailingAnchor, constant: Constants.horizontalInset),
            descriptionLabel.widthAnchor.constraint(equalToConstant: Constants.descriptionWidth),

            textFieldTitle.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 25),
            textFieldTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            view.trailingAnchor.constraint(equalTo: textFieldTitle.trailingAnchor, constant: Constants.horizontalInset),

            scrollView.topAnchor.constraint(equalTo: textFieldTitle.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.horizontalInset),
            view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: Constants.horizontalInset),
            scrollView.heightAnchor.constraint(equalToConstant: Constants.textViewHeight),
            view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: Constants.textViewBottomInset),

            view.trailingAnchor.constraint(equalTo: sendButton.trailingAnchor, constant: Constants.horizontalInset),
            view.bottomAnchor.constraint(equalTo: sendButton.bottomAnchor, constant: Constants.bottomInset),
            sendButton.leadingAnchor.constraint(equalTo: dontSendButton.trailingAnchor, constant: 12),
            view.bottomAnchor.constraint(equalTo: dontSendButton.bottomAnchor, constant: Constants.bottomInset),
        ])

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Esc declines, matching the close button. It goes through `addKeyEquivalent` rather than
        // `dontSendButton.keyEquivalent`, because the crash log text view is selectable, can take
        // first responder and swallows the key.
        addKeyEquivalent(.escape, modifierFlags: []) { [weak self] _ in
            guard let self else { return false }
            dontSendAction(self)
            return true
        }
    }

    private func updateView() {
        guard let content = crashReport?.content else {
            assertionFailure("CrashReportPromptViewController: Failed to get content")
            return
        }

        textView.string = content
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()

        // Closing the window with its close button is a decline, and reaches neither button action.
        answer(.deny)
    }

    /// Reports the answer once; whichever of the button actions and the window closing happens first wins.
    private func answer(_ response: CrashReportPromptPresenter.Response) {
        guard let userDidAnswerPrompt else { return }
        self.userDidAnswerPrompt = nil
        userDidAnswerPrompt(response)
    }

    @objc private func sendAction(_ sender: Any) {
        answer(.allow)
        view.window?.close()
    }

    @objc private func dontSendAction(_ sender: Any) {
        answer(.deny)
        view.window?.close()
    }

}
