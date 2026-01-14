//
//  AIChatSuggestionsView.swift
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

import AppKit
import AIChat
import Combine
import DesignResourcesKit

/// A view that displays a list of AI chat suggestions using an NSStackView.
/// Supports keyboard-based selection and mouse interaction.
final class AIChatSuggestionsView: NSView {

    private enum Constants {
        static let rowHeight: CGFloat = 32
        static let separatorHeight: CGFloat = 1
        static let separatorTopPadding: CGFloat = 8
        static let separatorBottomPadding: CGFloat = 4
        static let separatorHorizontalInset: CGFloat = 12
        static let rowsHorizontalPadding: CGFloat = 4
        static let bottomPadding: CGFloat = 4
    }

    // MARK: - UI Components

    private let separatorView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        return view
    }()

    /// Stack view for row views
    private let stackView: NSStackView = {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        return stack
    }()

    // MARK: - Properties

    private var rowViews: [AIChatSuggestionRowView] = []
    private var cancellables = Set<AnyCancellable>()
    private var previousSuggestionCount: Int = 0
    private weak var boundViewModel: AIChatSuggestionsViewModel?

    var onSuggestionClicked: ((AIChatSuggestion) -> Void)?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        addSubview(separatorView)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            separatorView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.separatorTopPadding),
            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.separatorHorizontalInset),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.separatorHorizontalInset),
            separatorView.heightAnchor.constraint(equalToConstant: Constants.separatorHeight),

            stackView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: Constants.separatorBottomPadding),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.rowsHorizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.rowsHorizontalPadding)
        ])

        updateSeparatorColor()
    }

    private func updateSeparatorColor() {
        separatorView.layer?.backgroundColor = NSColor(designSystemColor: .lines).cgColor
    }

    // MARK: - Static Height Calculation

    /// Calculates the required height for a given number of suggestions.
    /// This is a static calculation that doesn't depend on view state.
    static func calculateHeight(forSuggestionCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let separatorTotalHeight = Constants.separatorHeight + Constants.separatorTopPadding + Constants.separatorBottomPadding
        let rowsHeight = CGFloat(count) * Constants.rowHeight
        return separatorTotalHeight + rowsHeight + Constants.bottomPadding
    }

    // MARK: - Public Methods

    /// Updates the suggestions displayed in the view.
    /// - Parameters:
    ///   - suggestions: The list of suggestions to display.
    ///   - selectedIndex: The index of the currently selected suggestion (for keyboard navigation).
    ///   - isKeyboardNavigating: Whether keyboard navigation is currently active.
    /// - Returns: `true` if the suggestion count changed (requiring height update), `false` otherwise.
    @discardableResult
    func update(with suggestions: [AIChatSuggestion], selectedIndex: Int?, isKeyboardNavigating: Bool = false) -> Bool {
        let countChanged = suggestions.count != previousSuggestionCount
        previousSuggestionCount = suggestions.count

        // Remove existing row views
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        // Create new row views
        for (index, suggestion) in suggestions.enumerated() {
            let rowView = AIChatSuggestionRowView(suggestion: suggestion)
            rowView.translatesAutoresizingMaskIntoConstraints = false
            rowView.isSelected = (index == selectedIndex)
            rowView.isKeyboardNavigating = isKeyboardNavigating

            rowView.onClick = { [weak self] in
                self?.onSuggestionClicked?(suggestion)
            }

            rowView.onMouseMoved = { [weak self] in
                self?.boundViewModel?.acknowledgeMouseMovement()
            }

            stackView.addArrangedSubview(rowView)
            rowViews.append(rowView)

            // Pin row width to stack view
            rowView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        // Update visibility
        let hasSuggestions = !suggestions.isEmpty
        separatorView.isHidden = !hasSuggestions

        return countChanged
    }

    /// Updates only the selection state without rebuilding the entire view.
    /// - Parameters:
    ///   - selectedIndex: The index of the currently selected suggestion.
    ///   - isKeyboardNavigating: Whether keyboard navigation is currently active.
    func updateSelection(_ selectedIndex: Int?, isKeyboardNavigating: Bool = false) {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = (index == selectedIndex)
            rowView.isKeyboardNavigating = isKeyboardNavigating
            // Clear hover state when keyboard navigating
            if isKeyboardNavigating {
                rowView.isHovered = false
            }
        }
    }

    /// Binds the view to a view model for automatic updates.
    /// - Parameters:
    ///   - viewModel: The view model to bind to.
    ///   - onHeightChange: Called when the number of suggestions changes, requiring a height update.
    func bind(to viewModel: AIChatSuggestionsViewModel, onHeightChange: @escaping (CGFloat) -> Void) {
        boundViewModel = viewModel

        viewModel.$filteredSuggestions
            .combineLatest(viewModel.$selectedIndex, viewModel.$isKeyboardNavigating)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestions, selectedIndex, isKeyboardNavigating in
                guard let self else { return }
                let countChanged = self.update(with: suggestions, selectedIndex: selectedIndex, isKeyboardNavigating: isKeyboardNavigating)
                if countChanged {
                    let newHeight = AIChatSuggestionsView.calculateHeight(forSuggestionCount: suggestions.count)
                    onHeightChange(newHeight)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Appearance Updates

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSeparatorColor()
    }
}
