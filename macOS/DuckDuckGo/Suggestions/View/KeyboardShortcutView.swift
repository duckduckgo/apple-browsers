//
//  KeyboardShortcutView.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit

/// A view that displays keyboard shortcut indicators (e.g., ⌥ ↩ for Option+Return)
final class KeyboardShortcutView: NSView {

    private enum Constants {
        static let keyCapCornerRadius: CGFloat = 4
        static let keyCapSize: CGFloat = 16
        static let keyCapFontSize: CGFloat = 10
        static let keyCapSpacing: CGFloat = 4
        static let normalBackgroundColor = NSColor.black.withAlphaComponent(0.08)
        static let selectedBackgroundColor = NSColor.white.withAlphaComponent(0.15)
        static let normalTextColor = NSColor.suggestionText
        static let selectedTextColor = NSColor.selectedSuggestionTint
    }

    private let stackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = Constants.keyCapSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var keyCapViews: [KeyCapView] = []

    var isHighlighted: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Configures the view to display the given key symbols
    /// - Parameter symbols: Array of key symbols to display (e.g., ["⌥", "↩"])
    func configure(with symbols: [String]) {
        keyCapViews.forEach { $0.removeFromSuperview() }
        keyCapViews.removeAll()

        for symbol in symbols {
            let keyCapView = KeyCapView(symbol: symbol)
            keyCapViews.append(keyCapView)
            stackView.addArrangedSubview(keyCapView)
        }

        updateAppearance()
    }

    private func updateAppearance() {
        let bgColor = isHighlighted ? Constants.selectedBackgroundColor : Constants.normalBackgroundColor
        let textColor = isHighlighted ? Constants.selectedTextColor : Constants.normalTextColor

        keyCapViews.forEach { keyCapView in
            keyCapView.backgroundColor = bgColor
            keyCapView.textColor = textColor
        }
    }

    override var intrinsicContentSize: NSSize {
        let keyCapCount = CGFloat(keyCapViews.count)
        guard keyCapCount > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

        let width = (keyCapCount * Constants.keyCapSize) + ((keyCapCount - 1) * Constants.keyCapSpacing)
        return NSSize(width: width, height: Constants.keyCapSize)
    }
}

// MARK: - KeyCapView

private final class KeyCapView: NSView {

    private enum Constants {
        static let cornerRadius: CGFloat = 4
        static let size: CGFloat = 16
        static let fontSize: CGFloat = 10
    }

    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: Constants.fontSize, weight: .medium)
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    var backgroundColor: NSColor = .clear {
        didSet {
            layer?.backgroundColor = backgroundColor.cgColor
        }
    }

    var textColor: NSColor = .labelColor {
        didSet {
            label.textColor = textColor
        }
    }

    init(symbol: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.size, height: Constants.size))
        setupView(symbol: symbol)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView(symbol: "")
    }

    private func setupView(symbol: String) {
        wantsLayer = true
        layer?.cornerRadius = Constants.cornerRadius
        translatesAutoresizingMaskIntoConstraints = false

        label.stringValue = symbol
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Constants.size),
            heightAnchor.constraint(equalToConstant: Constants.size),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
