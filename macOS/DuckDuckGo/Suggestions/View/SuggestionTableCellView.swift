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

import Cocoa
import Common
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
        static let textColor: NSColor = .suggestionText
        static let suffixColor: NSColor = .addressBarSuffix
        static let burnerSuffixColor: NSColor = .burnerAccent
        static let iconColor: NSColor = .suggestionIcon
        static let selectedTintColor: NSColor = .selectedSuggestionTint

        static let switchToTabExtraSpace: CGFloat = 12 + 6 + 9 + 12
        static let switchToTabSuffixPadding: CGFloat = 8

        static let trailingSpace: CGFloat = 8
        static let iconImageViewLeadingSpace: CGFloat = 13
        static let suggestionTextFieldLeadingSpace: CGFloat = 7
    }

    @IBOutlet var iconImageView: NSImageView!
    @IBOutlet var removeButton: NSButton!
    @IBOutlet var suffixTextField: NSTextField!
    @IBOutlet var suffixTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var switchToTabBox: ColorView!
    @IBOutlet var switchToTabLabel: NSTextField!
    @IBOutlet var switchToTabArrowView: NSImageView!
    @IBOutlet var switchToTabBoxLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var switchToTabBoxTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var iconImageViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var searchSuggestionTextFieldLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var switchToTabLabelLeadingConstraint: NSLayoutConstraint!

    private lazy var keyboardShortcutView: KeyboardShortcutView = {
        let view = KeyboardShortcutView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: ["⌃", "⏎"])
        return view
    }()

    private var labelLeadingToShortcutsConstraint: NSLayoutConstraint?

    var theme: ThemeStyleProviding?
    var suggestion: Suggestion?
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

    override func awakeFromNib() {
        suffixTextField.textColor = Constants.suffixColor
        removeButton.toolTip = UserText.removeSuggestionTooltip
        switchToTabLabel.attributedStringValue = Self.switchToTabAttributedString
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
            .font: NSFont.systemFont(ofSize: 13)
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

        let usesTransparentBox: Bool
        if case .default = cellStyle {
            usesTransparentBox = false
        } else {
            usesTransparentBox = true
        }

        if isSelected {
            textField?.attributedStringValue = attributedString
            textField?.textColor = Constants.selectedTintColor
            suffixTextField.textColor = theme?.palette.accentContentSecondary ?? Constants.selectedTintColor
            switchToTabLabel.textColor = theme?.palette.accentContentSecondary ?? Constants.selectedTintColor
            switchToTabArrowView.contentTintColor = theme?.palette.accentContentSecondary ?? Constants.selectedTintColor
            switchToTabBox.backgroundColor = usesTransparentBox ? .clear : .white.withAlphaComponent(0.09)
        } else {
            textField?.attributedStringValue = attributedString
            textField?.textColor = theme?.colorsProvider.addressBarTextFieldColor ?? Constants.textColor
            switchToTabLabel.textColor = theme?.palette.accentPrimary ?? Constants.textColor
            switchToTabArrowView.contentTintColor = theme?.palette.accentPrimary ?? Constants.textColor
            switchToTabBox.backgroundColor = usesTransparentBox ? .clear : .buttonMouseOver
            if isBurner {
                suffixTextField.textColor = Constants.burnerSuffixColor
            } else {
                suffixTextField.textColor = theme?.palette.accentPrimary ?? Constants.suffixColor
            }
        }

        updateKeyboardShortcutVisibility()
    }

    private func updateImageViews() {
        iconImageView.contentTintColor = isSelected ? Constants.selectedTintColor : Constants.iconColor
        removeButton.contentTintColor = isSelected ? Constants.selectedTintColor : Constants.iconColor
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

            if alwaysAnchorToTrailing {
                switchToTabBoxLeadingConstraint.isActive = false
                switchToTabBoxTrailingConstraint.isActive = true
                suffixTrailingConstraint.constant = boxWidth + Constants.trailingSpace + Constants.switchToTabSuffixPadding
            } else {
                var textWidth = attributedString?.boundingRect(with: bounds.size).width ?? 0
                if textWidth < bounds.width {
                    textWidth += suffixTextField.attributedStringValue.boundingRect(with: bounds.size).width
                }
                if textField!.frame.minX
                    + textWidth
                    + Constants.switchToTabSuffixPadding
                    + boxWidth
                    + Constants.trailingSpace > bounds.width {

                    switchToTabBoxLeadingConstraint.isActive = false
                    switchToTabBoxTrailingConstraint.isActive = true
                } else {
                    switchToTabBoxTrailingConstraint.isActive = false
                    switchToTabBoxLeadingConstraint.constant = textField!.frame.minX + textWidth + Constants.switchToTabSuffixPadding
                    switchToTabBoxLeadingConstraint.isActive = true
                    suffixTrailingConstraint.constant = Constants.trailingSpace
                }
            }
        }

        var iconLeadingPadding = theme?.addressBarStyleProvider.suggestionIconViewLeadingPadding ?? Constants.iconImageViewLeadingSpace
        if Application.appDelegate.featureFlagger.isFeatureOn(.aiChatOmnibarToggle) {
            iconLeadingPadding += 8
        }
        iconImageViewLeadingConstraint.constant = iconLeadingPadding
        searchSuggestionTextFieldLeadingConstraint.constant = theme?.addressBarStyleProvider.suggestionTextFieldLeadingPadding ?? Constants.suggestionTextFieldLeadingSpace

        super.layout()
    }
}
