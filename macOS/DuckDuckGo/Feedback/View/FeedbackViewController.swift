//
//  FeedbackViewController.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Common
import FoundationExtensions
import SwiftUI
import SwiftUIExtensions

final class FeedbackViewController: NSViewController {

    enum Constants {
        static let defaultContentHeight: CGFloat = 160
        static let feedbackContentHeight: CGFloat = 338
        static let thankYouContentHeight: CGFloat = 262
        static let browserFeedbackViewTopConstraint: CGFloat = 53
        static let unsupportedOSWarningHeight: CGFloat = 200
    }

    enum FormOption {
        case feedback(feedbackCategory: Feedback.Category)

        init?(tag: Int) {
            switch tag {
            case 1: self = FormOption.feedback(feedbackCategory: .bug)
            case 2: self = FormOption.feedback(feedbackCategory: .featureRequest)
            case 3: self = FormOption.feedback(feedbackCategory: .other)
            default: return nil
            }
        }

        var tag: Int {
            switch self {
            case .feedback(let feedbackCategory):
                switch feedbackCategory {
                case .bug, .firstTimeQuitSurvey: return 1
                case .featureRequest: return 2
                case .other: return 3
                case .generalFeedback, .designFeedback, .usability, .dataImport:
                    return -1 // Unsupported categories
                }
            }
        }
    }
    private(set) var titleLabel: NSTextField!
    private(set) var okButton: NSButton!
    private(set) var thankYouLabel: NSTextField!
    private(set) var cancelButton: NSButton!
    private(set) var feedbackHelpsLabel: NSTextField!

    private(set) var optionPopUpButton: NSPopUpButton!
    private(set) var pickOptionMenuItem: NSMenuItem!

    private(set) var contentView: ColorView!
    private(set) var contentViewHeightContraint: NSLayoutConstraint!

    private(set) var browserFeedbackView: NSView!
    private(set) var browserFeedbackViewTopConstraint: NSLayoutConstraint!

    private(set) var browserFeedbackDescriptionLabel: NSTextField!
    private(set) var browserFeedbackTextView: NSTextView!
    private(set) var browserFeedbackDisclaimerTextView: NSTextField!
    private(set) var unsupportedOsView: NSView!

    private(set) var submitButton: NSButton!

    private(set) var thankYouView: NSView!
    private var cancellables = Set<AnyCancellable>()

    private(set) var generalFeedbackItem: NSMenuItem!
    private(set) var requestFeatureItem: NSMenuItem!
    private(set) var reportProblemITem: NSMenuItem!

    private let supportedOSChecker = SupportedOSChecker()

    private enum LayoutConstants {
        static let contentSize = CGSize(width: 360, height: 769)
        static let headerHeight: CGFloat = 69
        static let footerHeight: CGFloat = 69
        static let contentHeight: CGFloat = 700
        static let browserFeedbackHeight: CGFloat = 290
        static let unsupportedOsHeight: CGFloat = 200
        static let contentTopOffset: CGFloat = 53
        static let inset: CGFloat = 20
        static let fieldWidth: CGFloat = 320
        static let buttonHeight: CGFloat = 28
        static let popUpHeight: CGFloat = 30
        static let textViewHeight: CGFloat = 97
        static let disclaimerHeight: CGFloat = 75
        static let feedbackHelpsHeight: CGFloat = 28
        static let thankYouImageSide: CGFloat = 96
        static let closeButtonSide: CGFloat = 20
    }

    private func makeDialogButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setContentHuggingPriority(.init(750), for: .vertical)
        return button
    }

    private func makeCenteredTitleLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .greyText
        label.setContentHuggingPriority(.init(251), for: .horizontal)
        label.setContentHuggingPriority(.init(750), for: .vertical)
        return label
    }

    // swiftlint:disable:next function_body_length
    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: LayoutConstants.contentSize))

        // MARK: Header
        let headerView = ColorView(frame: .zero, backgroundColor: .firePopoverPanelBackground)
        headerView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel = makeCenteredTitleLabel("")

        // Hidden in the storyboard and never shown from code; kept so the layout matches.
        let headerCloseButton = NSButton(frame: .zero)
        headerCloseButton.translatesAutoresizingMaskIntoConstraints = false
        headerCloseButton.isHidden = true
        headerCloseButton.setButtonType(.momentaryPushIn)
        headerCloseButton.isBordered = false
        headerCloseButton.bezelStyle = .shadowlessSquare
        headerCloseButton.image = .close
        headerCloseButton.imagePosition = .imageOnly
        headerCloseButton.imageScaling = .scaleProportionallyUpOrDown
        headerCloseButton.alignment = .center

        headerView.addSubview(titleLabel)
        headerView.addSubview(headerCloseButton)

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        separator.setContentHuggingPriority(.init(750), for: .vertical)

        // MARK: Thank you
        thankYouView = NSView()
        thankYouView.translatesAutoresizingMaskIntoConstraints = false
        thankYouView.isHidden = true

        okButton = makeDialogButton(title: "", action: #selector(okButtonAction(_:)))
        okButton.keyEquivalent = "\r"

        let thankYouImageView = NSImageView()
        thankYouImageView.translatesAutoresizingMaskIntoConstraints = false
        thankYouImageView.image = .thankYou
        thankYouImageView.imageScaling = .scaleProportionallyDown
        thankYouImageView.imageAlignment = .alignLeft
        thankYouImageView.refusesFirstResponder = true
        thankYouImageView.setContentHuggingPriority(.init(251), for: .horizontal)
        thankYouImageView.setContentHuggingPriority(.init(251), for: .vertical)

        thankYouLabel = makeCenteredTitleLabel("")

        feedbackHelpsLabel = NSTextField(labelWithString: "")
        feedbackHelpsLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackHelpsLabel.alignment = .center
        feedbackHelpsLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        feedbackHelpsLabel.textColor = .secondaryLabelColor
        feedbackHelpsLabel.setContentHuggingPriority(.init(251), for: .horizontal)
        feedbackHelpsLabel.setContentHuggingPriority(.init(750), for: .vertical)

        thankYouView.addSubview(okButton)
        thankYouView.addSubview(thankYouImageView)
        thankYouView.addSubview(thankYouLabel)
        thankYouView.addSubview(feedbackHelpsLabel)

        // MARK: Content
        contentView = ColorView(frame: .zero, backgroundColor: .interfaceBackground)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        pickOptionMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        pickOptionMenuItem.tag = -1
        pickOptionMenuItem.state = .on
        reportProblemITem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        reportProblemITem.tag = 1
        requestFeatureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        requestFeatureItem.tag = 2
        generalFeedbackItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        generalFeedbackItem.tag = 3

        let optionMenu = NSMenu()
        optionMenu.autoenablesItems = false
        optionMenu.items = [pickOptionMenuItem, .separator(), reportProblemITem, requestFeatureItem, generalFeedbackItem]

        optionPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        optionPopUpButton.translatesAutoresizingMaskIntoConstraints = false
        optionPopUpButton.bezelStyle = .regularSquare
        optionPopUpButton.alignment = .left
        optionPopUpButton.font = .menuFont(ofSize: 0)
        optionPopUpButton.autoenablesItems = false
        optionPopUpButton.menu = optionMenu
        optionPopUpButton.select(pickOptionMenuItem)
        optionPopUpButton.target = self
        optionPopUpButton.action = #selector(optionPopUpButtonAction(_:))
        (optionPopUpButton.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail

        // MARK: Browser feedback
        browserFeedbackView = NSView()
        browserFeedbackView.translatesAutoresizingMaskIntoConstraints = false
        browserFeedbackView.isHidden = true

        browserFeedbackDescriptionLabel = NSTextField(labelWithString: "")
        browserFeedbackDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        browserFeedbackDescriptionLabel.font = .controlContentFont(ofSize: 0)
        browserFeedbackDescriptionLabel.setContentHuggingPriority(.init(251), for: .horizontal)
        browserFeedbackDescriptionLabel.setContentHuggingPriority(.init(750), for: .vertical)

        browserFeedbackTextView = NSTextView()
        browserFeedbackTextView.importsGraphics = false
        browserFeedbackTextView.isRichText = false
        browserFeedbackTextView.isVerticallyResizable = true
        browserFeedbackTextView.smartInsertDeleteEnabled = true
        browserFeedbackTextView.textColor = .textColor
        browserFeedbackTextView.backgroundColor = .textBackgroundColor
        browserFeedbackTextView.insertionPointColor = .textColor
        browserFeedbackTextView.minSize = NSSize(width: 305, height: LayoutConstants.textViewHeight)
        browserFeedbackTextView.maxSize = NSSize(width: LayoutConstants.fieldWidth, height: CGFloat.greatestFiniteMagnitude)
        browserFeedbackTextView.autoresizingMask = [.width, .height]

        let feedbackScrollView = NSScrollView()
        feedbackScrollView.translatesAutoresizingMaskIntoConstraints = false
        feedbackScrollView.focusRingType = .exterior
        feedbackScrollView.borderType = .noBorder
        feedbackScrollView.hasHorizontalScroller = false
        feedbackScrollView.hasVerticalScroller = true
        feedbackScrollView.contentView.drawsBackground = false
        feedbackScrollView.documentView = browserFeedbackTextView

        browserFeedbackDisclaimerTextView = NSTextField(wrappingLabelWithString: "")
        browserFeedbackDisclaimerTextView.translatesAutoresizingMaskIntoConstraints = false
        browserFeedbackDisclaimerTextView.font = .controlContentFont(ofSize: 0)
        browserFeedbackDisclaimerTextView.textColor = .secondaryLabelColor
        browserFeedbackDisclaimerTextView.isSelectable = false
        browserFeedbackDisclaimerTextView.setContentHuggingPriority(.init(251), for: .horizontal)
        browserFeedbackDisclaimerTextView.setContentHuggingPriority(.init(750), for: .vertical)

        browserFeedbackView.addSubview(browserFeedbackDescriptionLabel)
        browserFeedbackView.addSubview(feedbackScrollView)
        browserFeedbackView.addSubview(browserFeedbackDisclaimerTextView)

        unsupportedOsView = ColorView(frame: .zero, cornerRadius: 8)
        unsupportedOsView.translatesAutoresizingMaskIntoConstraints = false
        unsupportedOsView.isHidden = true

        let footerView = ColorView(frame: .zero, backgroundColor: .interfaceBackground)
        footerView.translatesAutoresizingMaskIntoConstraints = false

        submitButton = makeDialogButton(title: "", action: #selector(submitButtonAction(_:)))
        submitButton.isEnabled = false
        cancelButton = makeDialogButton(title: "", action: #selector(cancelButtonAction(_:)))

        contentView.addSubview(optionPopUpButton)
        contentView.addSubview(browserFeedbackView)
        contentView.addSubview(unsupportedOsView)
        contentView.addSubview(footerView)
        contentView.addSubview(submitButton)
        contentView.addSubview(cancelButton)

        view.addSubview(headerView)
        view.addSubview(separator)
        view.addSubview(thankYouView)
        view.addSubview(contentView)

        contentViewHeightContraint = contentView.heightAnchor.constraint(equalToConstant: LayoutConstants.contentHeight)
        browserFeedbackViewTopConstraint = browserFeedbackView.topAnchor
            .constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.contentTopOffset)

        NSLayoutConstraint.activate([
            headerView.heightAnchor.constraint(equalToConstant: LayoutConstants.headerHeight),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: LayoutConstants.inset),
            headerView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: LayoutConstants.inset),

            headerCloseButton.widthAnchor.constraint(equalToConstant: LayoutConstants.closeButtonSide),
            headerCloseButton.heightAnchor.constraint(equalToConstant: LayoutConstants.closeButtonSide),
            headerCloseButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            headerCloseButton.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            thankYouView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            thankYouView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: thankYouView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: thankYouView.bottomAnchor),

            okButton.heightAnchor.constraint(equalToConstant: LayoutConstants.buttonHeight),
            okButton.leadingAnchor.constraint(equalTo: thankYouView.leadingAnchor, constant: LayoutConstants.inset),
            thankYouView.trailingAnchor.constraint(equalTo: okButton.trailingAnchor, constant: LayoutConstants.inset),
            thankYouView.bottomAnchor.constraint(equalTo: okButton.bottomAnchor, constant: LayoutConstants.inset),

            thankYouImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.thankYouImageSide),
            thankYouImageView.heightAnchor.constraint(equalToConstant: LayoutConstants.thankYouImageSide),
            thankYouImageView.centerXAnchor.constraint(equalTo: thankYouView.centerXAnchor),
            thankYouImageView.topAnchor.constraint(equalTo: thankYouView.topAnchor, constant: LayoutConstants.inset),

            thankYouLabel.centerXAnchor.constraint(equalTo: thankYouView.centerXAnchor),
            thankYouLabel.topAnchor.constraint(equalTo: thankYouImageView.bottomAnchor, constant: 8),

            feedbackHelpsLabel.heightAnchor.constraint(equalToConstant: LayoutConstants.feedbackHelpsHeight),
            feedbackHelpsLabel.widthAnchor.constraint(equalToConstant: LayoutConstants.fieldWidth),
            feedbackHelpsLabel.leadingAnchor.constraint(equalTo: thankYouView.leadingAnchor, constant: LayoutConstants.inset),
            thankYouView.trailingAnchor.constraint(equalTo: feedbackHelpsLabel.trailingAnchor, constant: LayoutConstants.inset),
            feedbackHelpsLabel.topAnchor.constraint(equalTo: thankYouLabel.bottomAnchor, constant: 8),

            contentView.topAnchor.constraint(equalTo: view.topAnchor, constant: LayoutConstants.headerHeight),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentViewHeightContraint,

            optionPopUpButton.heightAnchor.constraint(equalToConstant: LayoutConstants.popUpHeight),
            optionPopUpButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            optionPopUpButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: LayoutConstants.inset),
            contentView.trailingAnchor.constraint(equalTo: optionPopUpButton.trailingAnchor, constant: LayoutConstants.inset),

            browserFeedbackView.heightAnchor.constraint(equalToConstant: LayoutConstants.browserFeedbackHeight),
            browserFeedbackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: browserFeedbackView.trailingAnchor),
            browserFeedbackViewTopConstraint,

            browserFeedbackDescriptionLabel.widthAnchor.constraint(equalToConstant: LayoutConstants.fieldWidth),
            browserFeedbackDescriptionLabel.topAnchor.constraint(equalTo: browserFeedbackView.topAnchor, constant: 12),
            browserFeedbackDescriptionLabel.leadingAnchor.constraint(equalTo: browserFeedbackView.leadingAnchor,
                                                                     constant: LayoutConstants.inset),
            browserFeedbackView.trailingAnchor.constraint(equalTo: browserFeedbackDescriptionLabel.trailingAnchor,
                                                          constant: LayoutConstants.inset),

            feedbackScrollView.widthAnchor.constraint(equalToConstant: LayoutConstants.fieldWidth),
            feedbackScrollView.heightAnchor.constraint(equalToConstant: LayoutConstants.textViewHeight),
            feedbackScrollView.topAnchor.constraint(equalTo: browserFeedbackDescriptionLabel.bottomAnchor, constant: 8),
            feedbackScrollView.leadingAnchor.constraint(equalTo: browserFeedbackView.leadingAnchor,
                                                        constant: LayoutConstants.inset),
            browserFeedbackView.trailingAnchor.constraint(equalTo: feedbackScrollView.trailingAnchor,
                                                          constant: LayoutConstants.inset),

            browserFeedbackDisclaimerTextView.widthAnchor.constraint(equalToConstant: LayoutConstants.fieldWidth),
            browserFeedbackDisclaimerTextView.heightAnchor.constraint(equalToConstant: LayoutConstants.disclaimerHeight),
            browserFeedbackDisclaimerTextView.topAnchor.constraint(equalTo: feedbackScrollView.bottomAnchor,
                                                                   constant: LayoutConstants.inset),
            browserFeedbackDisclaimerTextView.leadingAnchor.constraint(equalTo: browserFeedbackView.leadingAnchor,
                                                                       constant: LayoutConstants.inset),
            browserFeedbackView.trailingAnchor.constraint(equalTo: browserFeedbackDisclaimerTextView.trailingAnchor,
                                                          constant: LayoutConstants.inset),

            unsupportedOsView.heightAnchor.constraint(equalToConstant: LayoutConstants.unsupportedOsHeight),
            unsupportedOsView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.contentTopOffset),
            unsupportedOsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: unsupportedOsView.trailingAnchor),

            footerView.heightAnchor.constraint(equalToConstant: LayoutConstants.footerHeight),
            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: footerView.bottomAnchor),

            cancelButton.heightAnchor.constraint(equalToConstant: LayoutConstants.buttonHeight),
            cancelButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: LayoutConstants.inset),
            contentView.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: LayoutConstants.inset),

            submitButton.heightAnchor.constraint(equalToConstant: LayoutConstants.buttonHeight),
            submitButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 12),
            submitButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor),
            contentView.trailingAnchor.constraint(equalTo: submitButton.trailingAnchor, constant: LayoutConstants.inset),
            contentView.bottomAnchor.constraint(equalTo: submitButton.bottomAnchor, constant: LayoutConstants.inset),
        ])

        self.view = view
    }

    var currentTab: Tab?
    var currentTabUrl: URL? {
        guard let url = currentTab?.content.urlForWebView else {
            return nil
        }

        // ⚠️ To limit privacy risk, site URL is trimmed to not include query and fragment
        return url.trimmingQueryItemsAndFragment()
    }

    /// Optional pre-selected form option to initialize the feedback form with
    var preselectedFormOption: FormOption? {
        didSet {
            setupPreselectedOption()
        }
    }

    private let feedbackSender = FeedbackSender()

    override func viewDidLoad() {
        super.viewDidLoad()

        setContentViewHeight(Constants.defaultContentHeight, animated: false)
        setupTextViews()
        setupPreselectedOption()
        setupKeyEquivalents()
    }

    /// Esc and ⌘↩ are handled as key equivalents rather than as button `keyEquivalent`s:
    /// the message text view is usually first responder and swallows both.
    private func setupKeyEquivalents() {
        addKeyEquivalent(.escape, modifierFlags: []) { [weak self] _ in
            guard let self else { return false }
            cancelButtonAction(self)
            return true
        }
        addKeyEquivalent("\r", modifierFlags: .command) { [weak self] _ in
            guard let self, submitButton.isEnabled else { return false }
            submitButtonAction(self)
            return true
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(popUpButtonOpened(_:)),
                                               name: NSPopUpButton.willPopUpNotification,
                                               object: nil)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()

        // swiftlint:disable notification_center_detachment
        NotificationCenter.default.removeObserver(self)
        // swiftlint:enable notification_center_detachment
    }

    @objc func optionPopUpButtonAction(_ sender: Any) {
        updateViews()
    }

    @objc func websiteBreakageCategoryPopUpButtonAction(_ sender: Any) {
        updateViews()
    }

    @objc func popUpButtonOpened(_ notification: Notification) {
        guard let popUpButton = notification.object as? NSPopUpButton else {
            assertionFailure("No popup button")
            return
        }

        if popUpButton == optionPopUpButton {
            pickOptionMenuItem.isEnabled = false
        }
    }

    @objc func submitButtonAction(_ sender: Any) {
        switch selectedFormOption {
        case .none: assertionFailure("Submit shouldn't be enabled"); return
        case .feedback: sendFeedback()
        }

        showThankYou()
    }

    @objc func okButtonAction(_ sender: Any) {
        guard let window = view.window,
              let sheetParent = window.sheetParent else {
                  assertionFailure("No sheet parent")
                  return
              }

        sheetParent.endSheet(window, returnCode: .OK)
    }

    @objc func cancelButtonAction(_ sender: Any) {
        guard let window = self.view.window,
              let sheetParent = window.sheetParent else {
                  assertionFailure("No sheet parent")
                  return
              }

        sheetParent.endSheet(window, returnCode: .cancel)
    }

    private func setupTextViews() {
        browserFeedbackTextView.delegate = self
        browserFeedbackTextView.font = NSFont.systemFont(ofSize: 12)
        titleLabel.stringValue = UserText.browserFeedbackTitle
        okButton.title = UserText.ok
        thankYouLabel.stringValue = UserText.browserFeedbackThankYou
        feedbackHelpsLabel.stringValue = UserText.browserFeedbackFeedbackHelps
        cancelButton.title = UserText.cancel
        submitButton.title = UserText.submit
        generalFeedbackItem.title = UserText.browserFeedbackGeneralFeedback
        requestFeatureItem.title = UserText.browserFeedbackRequestFeature
        reportProblemITem.title = UserText.browserFeedbackReportProblem
        pickOptionMenuItem.title = UserText.browserFeedbackSelectCategory
    }

    private var selectedFormOption: FormOption? {
        guard let item = optionPopUpButton.selectedItem, item.tag >= 0 else {
            return nil
        }

        return FormOption(tag: item.tag)
    }

    private func updateViews() {
        defer {
            updateSubmitButton()
        }

        guard let selectedFormOption = selectedFormOption else {
            browserFeedbackView.isHidden = true
            setContentViewHeight(Constants.defaultContentHeight, animated: false)
            pickOptionMenuItem.isEnabled = true
            return
        }

        browserFeedbackView.isHidden = false

        showUnsupportedOsViewIfNeeded()
        let unsupportedOSWarningHeight = supportedOSChecker.showsSupportWarning ? Constants.unsupportedOSWarningHeight : 0

        let contentHeight: CGFloat
        switch selectedFormOption {
        case .feedback(let feedbackCategory):
            contentHeight = Constants.feedbackContentHeight + unsupportedOSWarningHeight
            updateBrowserFeedbackDescriptionLabel(for: feedbackCategory)
            browserFeedbackViewTopConstraint.constant = Constants.browserFeedbackViewTopConstraint + unsupportedOSWarningHeight
        }
        updateBrowserFeedbackDisclaimerLabel(for: selectedFormOption)
        browserFeedbackTextView.makeMeFirstResponder()
        setContentViewHeight(contentHeight, animated: true)
    }

    private func setContentViewHeight(_ height: CGFloat, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { [weak self] context in
                context.duration = 1/6
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self?.contentViewHeightContraint.animator().constant = height
            }
        } else {
            contentViewHeightContraint.constant = height
        }
    }

    private func updateSubmitButton() {
        guard let selectedFormOption = selectedFormOption else {
            submitButton.isEnabled = false
            return
        }

        switch selectedFormOption {
        case .feedback:
            if !browserFeedbackTextView.string.trimmingWhitespace().isEmpty {
                submitButton.isEnabled = true
            } else {
                submitButton.isEnabled = false
            }
        }

        submitButton.bezelColor = submitButton.isEnabled ? NSColor.controlAccentColor: nil
    }

    private func updateBrowserFeedbackDescriptionLabel(for category: Feedback.Category) {
        switch category {
        case .bug, .firstTimeQuitSurvey:
            browserFeedbackDescriptionLabel.stringValue = UserText.feedbackBugDescription
        case .featureRequest:
            browserFeedbackDescriptionLabel.stringValue = UserText.feedbackFeatureRequestDescription
        case .other:
            browserFeedbackDescriptionLabel.stringValue = UserText.feedbackOtherDescription
        case .generalFeedback, .designFeedback, .usability, .dataImport:
            assertionFailure("unexpected flow")
            browserFeedbackDescriptionLabel.stringValue = "\(category)"
        }
    }

    private func updateBrowserFeedbackDisclaimerLabel(for formOption: FormOption) {
        switch formOption {
        case .feedback:
            browserFeedbackDisclaimerTextView.stringValue = UserText.feedbackDisclaimer
        }
    }

    private func sendFeedback() {
        guard let selectedFormOption = selectedFormOption else {
            assertionFailure("Can't send feedback")
            return
        }

        switch selectedFormOption {
        case .feedback(feedbackCategory: let feedbackCategory):
            let feedback = Feedback(category: feedbackCategory,
                                    comment: browserFeedbackTextView.string,
                                    appVersion: "\(AppVersion.shared.versionNumber)",
                                    osVersion: "\(ProcessInfo.processInfo.operatingSystemVersion)")
            feedbackSender.sendFeedback(feedback)
        }
    }

    private func showThankYou() {
        setContentViewHeight(Constants.thankYouContentHeight, animated: true)
        contentView.isHidden = true
        thankYouView.isHidden = false
    }

    private weak var unsupportedOsChildView: NSView?
    private func showUnsupportedOsViewIfNeeded() {
        if supportedOSChecker.showsSupportWarning,
           unsupportedOsChildView == nil {

            let canUpgradeOS = OSUpgradeCapabilityOverridePersistor()
                .canUpgradeOS(default: supportedOSChecker.osUpgradeCapability.canUpgradeOS)
            let view = NSHostingView(rootView: Preferences.UnsupportedDeviceInfoBox(canUpgradeOS: canUpgradeOS).padding(.horizontal, 20))
            unsupportedOsView.addAndLayout(view)
            unsupportedOsView.isHidden = false
            unsupportedOsChildView = view
        }
    }

    private func setupPreselectedOption() {
        guard let preselectedFormOption = preselectedFormOption else {
            return
        }

        let tag = preselectedFormOption.tag
        guard tag >= 0, let menuItem = optionPopUpButton.menu?.item(withTag: tag) else {
            return
        }

        optionPopUpButton.select(menuItem)
        updateViews()
    }

}

extension FeedbackViewController: NSTextFieldDelegate {

    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        return true
    }

    func controlTextDidChange(_ notification: Notification) {
        updateSubmitButton()
    }

}

extension FeedbackViewController: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        updateSubmitButton()
    }

}

fileprivate extension URL {

    func trimmingQueryItemsAndFragment() -> URL? {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
        components?.queryItems = nil
        components?.fragment = nil

        return components?.url
    }

}
