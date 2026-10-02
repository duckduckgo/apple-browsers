//
//  SuggestionTableCellView.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Cocoa
import Common
import FoundationExtensions
import os.log
import Suggestions

final class SuggestionTableCellView: NSTableCellView {

    static let identifier = NSUserInterfaceItemIdentifier("SuggestionTableCellView")

    enum CellStyle {
        case `default`
        case aiChat
        case search
        case visit(host: String)
    }

    private enum Constants {
        static let switchToTabExtraSpace: CGFloat = 12 + 6 + 9 + 12
        static let switchToTabSuffixPadding: CGFloat = 8

        static let trailingSpace: CGFloat = 8
        static let iconImageViewLeadingSpace: CGFloat = 13
    }

    var iconImageView: NSImageView!
    var removeButton: NSButton!
    var suffixTextField: NSTextField!
    var suffixTrailingConstraint: NSLayoutConstraint!
    var switchToTabBox: ColorView!
    var switchToTabLabel: NSTextField!
    var switchToTabArrowView: NSImageView!
    var switchToTabBoxLeadingConstraint: NSLayoutConstraint!
    var switchToTabBoxTrailingConstraint: NSLayoutConstraint!
    var iconImageViewLeadingConstraint: NSLayoutConstraint!
    var searchSuggestionTextFieldLeadingConstraint: NSLayoutConstraint!
    var switchToTabLabelLeadingConstraint: NSLayoutConstraint!
    private var confirmButton: NSButton!

    private lazy var keyboardShortcutView: KeyboardShortcutView = {
        let view = KeyboardShortcutView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: ["⌃", "⏎"])
        view.toolTip = "control + return"
        return view
    }()

    private var labelLeadingToShortcutsConstraint: NSLayoutConstraint?

    var theme: ThemeStyleProviding?
    var suggestion: Suggestion?
    var isAIChatToggleBeingDisplayed: Bool = false
    private(set) var cellStyle: CellStyle = .default

    static let switchToTabAttributedString: NSAttributedString = {
        let text = UserText.switchToTab
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .kern: 0.06,
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }()
    private static let switchToTabTextWidth: CGFloat = switchToTabAttributedString.size().width
    private static let switchToTabBoxWidth: CGFloat = switchToTabTextWidth + Constants.switchToTabExtraSpace

    static let searchTheWebAttributedString: NSAttributedString = {
        let text = UserText.searchTheWeb
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .kern: 0.06,
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }()
    private static let searchTheWebTextWidth: CGFloat = searchTheWebAttributedString.size().width
    private static let searchTheWebBoxWidth: CGFloat = searchTheWebTextWidth + Constants.switchToTabExtraSpace

    static let chatWithAIAttributedString: NSAttributedString = {
        let text = UserText.aiChatChatWithAITooltip
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .kern: 0.06,
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }()
    private static let chatWithAITextWidth: CGFloat = chatWithAIAttributedString.size().width
    private static let chatWithAIBoxWidth: CGFloat = chatWithAITextWidth + Constants.switchToTabExtraSpace

    private func setupKeyboardShortcutView() {
        guard keyboardShortcutView.superview == nil else { return }

        switchToTabBox.addSubview(keyboardShortcutView)

        NSLayoutConstraint.activate([
            keyboardShortcutView.leadingAnchor.constraint(equalTo: switchToTabBox.leadingAnchor, constant: 8),
            keyboardShortcutView.centerYAnchor.constraint(equalTo: switchToTabBox.centerYAnchor)
        ])

        labelLeadingToShortcutsConstraint = switchToTabLabel.leadingAnchor.constraint(
            equalTo: keyboardShortcutView.trailingAnchor,
            constant: 4
        )
    }

    private func updateKeyboardShortcutVisibility() {
        let showShortcuts: Bool
        if case .aiChat = cellStyle {
            showShortcuts = true
        } else {
            showShortcuts = false
        }

        keyboardShortcutView.isHidden = !showShortcuts
        keyboardShortcutView.isHighlighted = isSelected

        switchToTabLabelLeadingConstraint?.isActive = !showShortcuts
        labelLeadingToShortcutsConstraint?.isActive = showShortcuts
    }

    /// Builds the row: favicon, title, suffix, the "Switch to Tab" pill and a full-width
    /// invisible button that makes the whole row clickable.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        identifier = Self.identifier

        iconImageView = NSImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.imageAlignment = .alignLeft
        iconImageView.refusesFirstResponder = true
        iconImageView.setContentHuggingPriority(.init(251), for: .horizontal)
        iconImageView.setContentHuggingPriority(.init(251), for: .vertical)

        let titleTextField = NSTextField(labelWithString: "")
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.lineBreakMode = .byTruncatingTail
        titleTextField.textColor = .textColor
        titleTextField.setContentHuggingPriority(.init(252), for: .horizontal)
        titleTextField.setContentHuggingPriority(.init(750), for: .vertical)
        titleTextField.setContentCompressionResistancePriority(.init(252), for: .horizontal)

        suffixTextField = NSTextField(labelWithString: "")
        suffixTextField.translatesAutoresizingMaskIntoConstraints = false
        suffixTextField.lineBreakMode = .byTruncatingTail
        suffixTextField.font = .controlContentFont(ofSize: 0)
        suffixTextField.textColor = .controlAccentColor
        suffixTextField.setContentHuggingPriority(.init(251), for: .horizontal)
        suffixTextField.setContentHuggingPriority(.init(750), for: .vertical)
        suffixTextField.setContentCompressionResistancePriority(.init(252), for: .horizontal)

        switchToTabLabel = NSTextField(labelWithString: "")
        switchToTabLabel.translatesAutoresizingMaskIntoConstraints = false
        switchToTabLabel.lineBreakMode = .byClipping
        switchToTabLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        switchToTabLabel.setContentHuggingPriority(.init(750), for: .vertical)
        switchToTabLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        switchToTabArrowView = NSImageView()
        switchToTabArrowView.translatesAutoresizingMaskIntoConstraints = false
        switchToTabArrowView.image = .arrowRight12
        switchToTabArrowView.imageScaling = .scaleProportionallyDown
        switchToTabArrowView.imageAlignment = .alignLeft
        switchToTabArrowView.refusesFirstResponder = true
        switchToTabArrowView.animates = true
        switchToTabArrowView.contentTintColor = .labelColor
        switchToTabArrowView.setContentCompressionResistancePriority(.required, for: .horizontal)

        switchToTabBox = ColorView(frame: .zero, backgroundColor: .buttonMouseOver, cornerRadius: 6)
        switchToTabBox.translatesAutoresizingMaskIntoConstraints = false
        switchToTabBox.setContentHuggingPriority(.init(251), for: .horizontal)
        switchToTabBox.setContentHuggingPriority(.init(251), for: .vertical)
        switchToTabBox.setContentCompressionResistancePriority(.required, for: .horizontal)
        switchToTabBox.addSubview(switchToTabLabel)
        switchToTabBox.addSubview(switchToTabArrowView)

        // Full-size invisible button that makes the whole row clickable.
        confirmButton = NSButton(frame: .zero)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.setButtonType(.momentaryPushIn)
        confirmButton.isBordered = false
        confirmButton.bezelStyle = .shadowlessSquare
        confirmButton.imagePosition = .imageOnly
        confirmButton.imageScaling = .scaleProportionallyUpOrDown
        confirmButton.alignment = .center
        confirmButton.title = ""

        removeButton = NSButton(frame: .zero)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setButtonType(.momentaryPushIn)
        removeButton.isBordered = false
        removeButton.bezelStyle = .shadowlessSquare
        removeButton.image = .trash
        removeButton.imagePosition = .imageOnly
        removeButton.title = ""
        removeButton.alignment = .center

        addSubview(iconImageView)
        addSubview(titleTextField)
        addSubview(suffixTextField)
        addSubview(switchToTabBox)
        addSubview(confirmButton)
        addSubview(removeButton)
        textField = titleTextField

        iconImageViewLeadingConstraint = iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        searchSuggestionTextFieldLeadingConstraint = titleTextField.leadingAnchor
            .constraint(equalTo: iconImageView.trailingAnchor, constant: 8)
        switchToTabLabelLeadingConstraint = switchToTabLabel.leadingAnchor
            .constraint(equalTo: switchToTabBox.leadingAnchor, constant: 12)
        switchToTabBoxLeadingConstraint = switchToTabBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 450)
        switchToTabBoxLeadingConstraint.priority = .init(950)
        switchToTabBoxTrailingConstraint = trailingAnchor.constraint(equalTo: switchToTabBox.trailingAnchor, constant: 8)
        suffixTrailingConstraint = trailingAnchor.constraint(equalTo: suffixTextField.trailingAnchor, constant: 8)
        suffixTrailingConstraint.priority = .init(250)

        let removeButtonLeading = removeButton.leadingAnchor
            .constraint(equalTo: suffixTextField.trailingAnchor, constant: 8)
        removeButtonLeading.priority = .init(750)
        let suffixWidth = suffixTextField.widthAnchor.constraint(equalTo: titleTextField.widthAnchor, multiplier: 0.55)
        suffixWidth.priority = .init(250)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),
            iconImageViewLeadingConstraint,
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),

            searchSuggestionTextFieldLeadingConstraint,
            titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),

            suffixTextField.leadingAnchor.constraint(equalTo: titleTextField.trailingAnchor),
            suffixTextField.firstBaselineAnchor.constraint(equalTo: titleTextField.firstBaselineAnchor),
            suffixTrailingConstraint,
            suffixWidth,

            switchToTabBox.heightAnchor.constraint(equalToConstant: 22),
            switchToTabBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            switchToTabBoxLeadingConstraint,
            switchToTabBoxTrailingConstraint,

            switchToTabLabelLeadingConstraint,
            switchToTabLabel.centerYAnchor.constraint(equalTo: switchToTabBox.centerYAnchor),
            switchToTabArrowView.widthAnchor.constraint(equalToConstant: 9),
            switchToTabArrowView.heightAnchor.constraint(equalToConstant: 9),
            switchToTabArrowView.leadingAnchor.constraint(equalTo: switchToTabLabel.trailingAnchor, constant: 6),
            switchToTabArrowView.firstBaselineAnchor.constraint(equalTo: switchToTabLabel.firstBaselineAnchor),
            switchToTabBox.trailingAnchor.constraint(equalTo: switchToTabArrowView.trailingAnchor, constant: 12),

            confirmButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: confirmButton.trailingAnchor),
            confirmButton.topAnchor.constraint(equalTo: topAnchor),
            bottomAnchor.constraint(equalTo: confirmButton.bottomAnchor),

            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButtonLeading,
            trailingAnchor.constraint(equalTo: removeButton.trailingAnchor, constant: 11),
        ])

        let colorsProvider = theme?.colorsProvider

        /// `isBurner` isn't known until `display(_:isBurner:)` runs; this is the initial value it then corrects.
        suffixTextField.textColor = colorsProvider?.suggestionsSuffixColor(isBurner: isBurner)
        removeButton.toolTip = UserText.removeSuggestionTooltip
        switchToTabLabel.attributedStringValue = Self.switchToTabAttributedString
    }

    required init?(coder: NSCoder) {
        fatalError("\(SuggestionTableCellView.self): Bad initializer")
    }

    /// Wires the row-click and delete actions to the owning controller.
    func setActionTarget(_ target: AnyObject?, confirmAction: Selector, removeAction: Selector) {
        confirmButton.target = target
        confirmButton.action = confirmAction
        removeButton.target = target
        removeButton.action = removeAction
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        updateDeleteImageViewVisibility()
    }

    var isSelected: Bool = false {
        didSet {
            updateImageViews()
            updateTextField()
            updateDeleteImageViewVisibility()
        }
    }

    var isBurner: Bool = false

    func display(_ suggestionViewModel: SuggestionViewModel, isBurner: Bool) {
        self.cellStyle = .default
        self.isBurner = isBurner
        self.suggestion = suggestionViewModel.suggestion

        attributedString = suggestionViewModel.tableCellViewAttributedString
        iconImageView.image = suggestionViewModel.icon
        if let suffix = suggestionViewModel.suffix, !suffix.isEmpty {
            suffixTextField.stringValue = " – " + suffix
        } else {
            suffixTextField.stringValue = ""
        }
        setRemoveButtonHidden(true)
        if case .openTab = suggestionViewModel.suggestion,
           frame.size.width > 272 {
            switchToTabBox.isHidden = false
            switchToTabLabel.attributedStringValue = Self.switchToTabAttributedString
            switchToTabArrowView.isHidden = false
        } else {
            switchToTabBox.isHidden = true
        }

        updateTextField()
    }

    /// Displays the cell in a specific style with user-typed text
    /// - Parameters:
    ///   - userText: The text the user is typing in the address bar
    ///   - style: The cell style to use (.search or .aiChat)
    ///   - icon: Optional icon to display
    ///   - isBurner: Whether this is a burner window
    func display(userText: String, style: CellStyle, icon: NSImage?, isBurner: Bool) {
        self.cellStyle = style
        self.isBurner = isBurner
        self.suggestion = nil

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .paragraphStyle: SuggestionViewModel.paragraphStyle
        ]
        attributedString = NSAttributedString(string: userText, attributes: attributes)
        iconImageView.image = icon

        switch style {
        case .search:
            suffixTextField.stringValue = " – DuckDuckGo"
            switchToTabBox.isHidden = frame.size.width <= 272
            switchToTabLabel.attributedStringValue = Self.searchTheWebAttributedString
            switchToTabArrowView.isHidden = false
        case .aiChat:
            suffixTextField.stringValue = " – Duck.ai"
            switchToTabBox.isHidden = frame.size.width <= 272
            switchToTabLabel.attributedStringValue = Self.chatWithAIAttributedString
            switchToTabArrowView.isHidden = false
            setupKeyboardShortcutView()
        case .visit(let host):
            suffixTextField.stringValue = " – \(UserText.addressBarVisitSuffix) \(host)"
            switchToTabBox.isHidden = true
        case .default:
            suffixTextField.stringValue = ""
            switchToTabBox.isHidden = true
        }

        setRemoveButtonHidden(true)
        updateKeyboardShortcutVisibility()
        updateTextField()
    }

    private var attributedString: NSAttributedString?

    private func updateTextField() {
        guard let attributedString = attributedString else {
            Logger.general.error("SuggestionTableCellView: Attributed strings are nil")
            return
        }

        guard let theme else {
            assertionFailure()
            return
        }

        let usesTransparentBox: Bool
        if case .default = cellStyle {
            usesTransparentBox = false
        } else {
            usesTransparentBox = true
        }

        let colorsProvider = theme.colorsProvider
        let textColor = isSelected ? colorsProvider.suggestionsHighlightTextColor : colorsProvider.suggestionsTextColor
        let suffixColor = suggestionsSuffixColor(colorsProvider: colorsProvider)

        textField?.attributedStringValue = attributedString
        textField?.textColor = textColor
        suffixTextField.textColor = suffixColor
        switchToTabLabel.textColor = suffixColor
        switchToTabArrowView.contentTintColor = suffixColor

        if isSelected {
            switchToTabBox.backgroundColor = usesTransparentBox ? .clear : .white.withAlphaComponent(0.09)
        } else {
            switchToTabBox.backgroundColor = usesTransparentBox ? .clear : .buttonMouseOver
        }

        updateKeyboardShortcutVisibility()
    }

    private func updateImageViews() {
        guard let theme else {
            assertionFailure()
            return
        }

        let colorsProvider = theme.colorsProvider
        let tintColor = isSelected ? colorsProvider.suggestionsHighlightTextColor : colorsProvider.suggestionsTextColor

        iconImageView.contentTintColor = tintColor
        removeButton.contentTintColor = tintColor
    }

    func updateDeleteImageViewVisibility() {
        guard let window = window else { return }
        let mouseLocation = NSEvent.mouseLocation
        let windowFrameInScreen = window.frame

        // If the suggestion is based on history, if the mouse is inside the window's frame and
        // the suggestion is selected, show the delete button
        if let suggestion, suggestion.isHistoryEntry, windowFrameInScreen.contains(mouseLocation) {
            setRemoveButtonHidden(!isSelected)
        } else {
            setRemoveButtonHidden(true)
        }
    }

    private func setRemoveButtonHidden(_ hidden: Bool) {
        removeButton.isHidden = hidden
        suffixTrailingConstraint.priority = hidden ? .required : .defaultLow
    }

    override func layout() {
        if switchToTabBox.isHidden {
            switchToTabBoxLeadingConstraint.isActive = false
            switchToTabBoxTrailingConstraint.isActive = false
            suffixTrailingConstraint.constant = Constants.trailingSpace
        } else {
            let boxWidth: CGFloat
            let keyboardShortcutsWidth: CGFloat = 48
            switch cellStyle {
            case .search:
                boxWidth = Self.searchTheWebBoxWidth
            case .aiChat:
                boxWidth = Self.chatWithAIBoxWidth + keyboardShortcutsWidth
            case .visit, .default:
                boxWidth = Self.switchToTabBoxWidth
            }

            let alwaysAnchorToTrailing: Bool
            switch cellStyle {
            case .search, .aiChat:
                alwaysAnchorToTrailing = true
            case .visit, .default:
                alwaysAnchorToTrailing = false
            }

            let textWidth = calculateTextWidth()

            if alwaysAnchorToTrailing || contentExceedsAvailableWidth(textWidth: textWidth, boxWidth: boxWidth, bounds: bounds) {
                switchToTabBoxLeadingConstraint.isActive = false
                switchToTabBoxTrailingConstraint.isActive = true
                suffixTrailingConstraint.constant = boxWidth + Constants.trailingSpace + Constants.switchToTabSuffixPadding
            } else {
                switchToTabBoxTrailingConstraint.isActive = false
                switchToTabBoxLeadingConstraint.constant = textField!.frame.minX + textWidth + Constants.switchToTabSuffixPadding
                switchToTabBoxLeadingConstraint.isActive = true
                suffixTrailingConstraint.constant = Constants.trailingSpace
            }
        }

        guard let styleProvider = theme?.addressBarStyleProvider else {
            assertionFailure()
            return
        }

        var iconLeadingPadding = styleProvider.suggestionIconViewLeadingPadding
        if isAIChatToggleBeingDisplayed {
            iconLeadingPadding += 8
        }
        iconImageViewLeadingConstraint.constant = iconLeadingPadding
        searchSuggestionTextFieldLeadingConstraint.constant = styleProvider.suggestionTextFieldLeadingPadding

        super.layout()
    }
}

private extension SuggestionTableCellView {

    func contentExceedsAvailableWidth(textWidth: CGFloat, boxWidth: CGFloat, bounds: CGRect) -> Bool {
        (textField?.frame.minX ?? 0)
            + textWidth
            + Constants.switchToTabSuffixPadding
            + boxWidth
            + Constants.trailingSpace > bounds.width
    }

    func calculateTextWidth() -> CGFloat {
        var textWidth = attributedString?.boundingRect(with: bounds.size).width ?? 0
        if textWidth < bounds.width {
            textWidth += suffixTextField.attributedStringValue.boundingRect(with: bounds.size).width
        }

        return textWidth
    }

    func suggestionsSuffixColor(colorsProvider: ColorsProviding) -> NSColor {
        isSelected
            ? colorsProvider.suggestionsHighlightSuffixColor(isBurner: isBurner)
            : colorsProvider.suggestionsSuffixColor(isBurner: isBurner)
    }
}
