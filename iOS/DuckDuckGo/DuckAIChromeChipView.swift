//
//  DuckAIChromeChipView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import DesignResourcesKitIcons
import DesignResourcesKit

/// iPad Duck.ai chrome split-button. Left half opens a new Duck.ai tab (text);
/// right half toggles the current tab's contextual sheet (icon). Either half can
/// be shown or hidden independently from the chip's long-press menu.
final class DuckAIChromeChipView: UIView {

    enum SheetState {
        case closed
        case open
    }

    private enum Constants {
        static let cornerRadius: CGFloat = 9
        static let textPadding = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        static let iconButtonWidth: CGFloat = 40
        static let dividerWidth: CGFloat = 1
        static let dividerVerticalPadding: CGFloat = 6
    }

    private(set) lazy var textButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = UserText.actionOpenAIChat
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        config.contentInsets = Constants.textPadding
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .body,
                                                 compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.isPointerInteractionEnabled = true
        button.accessibilityLabel = UserText.accessibilityLabelOpenAIChat
        return button
    }()

    private(set) lazy var iconButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        config.contentInsets = .zero
        let button = UIButton(configuration: config)
        button.isPointerInteractionEnabled = true
        button.accessibilityLabel = UserText.actionToggleAIChatContextualSheet
        return button
    }()

    private lazy var divider: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .decorationSecondary)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var dividerContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: container.topAnchor, constant: Constants.dividerVerticalPadding),
            divider.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.dividerVerticalPadding),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        return container
    }()

    private(set) var sheetState: SheetState = .closed
    private var isTextVisible = true
    private var isIconVisible = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        layer.cornerRadius = Constants.cornerRadius
        layer.masksToBounds = true

        let stack = UIStackView(arrangedSubviews: [textButton, dividerContainer, iconButton])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerContainer.widthAnchor.constraint(equalToConstant: Constants.dividerWidth),
            iconButton.widthAnchor.constraint(equalToConstant: Constants.iconButtonWidth)
        ])

        setSheetState(.closed)
    }

    /// Swaps the icon glyph based on whether the contextual sheet is open.
    func setSheetState(_ state: SheetState) {
        sheetState = state
        let image: UIImage = {
            switch state {
            case .closed: return DesignSystemImages.Glyphs.Size24.sheet
            case .open:   return DesignSystemImages.Glyphs.Size24.sheetOpen
            }
        }()
        iconButton.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        iconButton.accessibilityValue = state == .open
            ? UserText.accessibilityValueAIChatContextualSheetOpen
            : UserText.accessibilityValueAIChatContextualSheetClosed
        iconButton.accessibilityTraits = state == .open ? [.button, .selected] : [.button]
    }

    /// Shows or hides the text half (opens a new Duck.ai tab).
    func setTextVisible(_ visible: Bool) {
        isTextVisible = visible
        textButton.isHidden = !visible
        updateDividerVisibility()
    }

    /// Shows or hides the icon half (contextual-sheet toggle).
    func setIconVisible(_ visible: Bool) {
        isIconVisible = visible
        iconButton.isHidden = !visible
        updateDividerVisibility()
    }

    /// The divider only makes sense when both halves are present.
    private func updateDividerVisibility() {
        dividerContainer.isHidden = !(isTextVisible && isIconVisible)
    }

}
