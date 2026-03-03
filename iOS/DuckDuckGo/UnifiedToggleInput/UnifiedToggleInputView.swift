//
//  UnifiedToggleInputView.swift
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

import Combine
import DesignResourcesKit
import UIKit

// MARK: - Delegate Protocol

/// Delegate protocol for handling interactions with the unified toggle input composite view.
protocol UnifiedToggleInputViewDelegate: AnyObject {
    func unifiedToggleInputViewDidTapWhileCollapsed(_ view: UnifiedToggleInputView)
    func unifiedToggleInputViewDidSubmitText(_ view: UnifiedToggleInputView, text: String, mode: TextEntryMode)
    func unifiedToggleInputViewDidChangeText(_ view: UnifiedToggleInputView, text: String)
    func unifiedToggleInputViewDidChangeMode(_ view: UnifiedToggleInputView, mode: TextEntryMode)
    func unifiedToggleInputViewDidTapVoice(_ view: UnifiedToggleInputView)
}

// MARK: - Card Position

/// Controls which corners are rounded and which direction shadows cast when expanded.
enum UnifiedToggleInputCardPosition {
    /// Bottom corners rounded, shadow downward (input at top of screen).
    case top
    /// Top corners rounded, shadow upward (input at bottom of screen, default).
    case bottom
}

// MARK: - View

/// Composite input bar wrapping `SwitchBarTextEntryView` (text core), `UnifiedToggleInputToggleView`,
/// and `UnifiedToggleInputToolbarView`. Using `SwitchBarTextEntryView` directly ensures improvements
/// to the omnibar text input are automatically inherited here.
///
/// Supports collapsed (single-line) and expanded (text + tools toolbar) layout states.
final class UnifiedToggleInputView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let collapsedCardHeight: CGFloat = 44
        static let cardHorizontalMargin: CGFloat = 16
        static let cardVerticalMargin: CGFloat = 8
        static let cardCornerRadiusExpanded: CGFloat = 24
        static let cardCornerRadiusCollapsed: CGFloat = 16
        static let toggleTopPadding: CGFloat = 8
        static let toggleBottomPadding: CGFloat = 4
        static let toggleHeight: CGFloat = 40
        static let toggleHorizontalPadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.25
    }

    // MARK: - Properties

    weak var delegate: UnifiedToggleInputViewDelegate?

    var cardPosition: UnifiedToggleInputCardPosition = .bottom

    var text: String {
        get { handler.currentText }
        set { textEntryView.setQueryText(newValue) }
    }

    var inputMode: TextEntryMode {
        handler.currentToggleState
    }

    private(set) var isExpanded = false

    var isToolbarSubmitHidden: Bool = false {
        didSet { toolsToolbar.isSubmitButtonHidden = isToolbarSubmitHidden }
    }

    /// Called inside animation blocks when a hierarchy-wide layout pass is needed
    /// so that sibling views (e.g. the content container) animate in sync.
    /// The owning view controller sets this.
    var onNeedsHierarchyLayout: (() -> Void)?

    var isVoiceSearchAvailable = false {
        didSet { handler.isVoiceSearchEnabled = isVoiceSearchAvailable }
    }

    // MARK: - Components

    private let handler: UnifiedToggleInputHandler
    private let textEntryView: SwitchBarTextEntryView
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private let cardView = UIView()
    private let toggleView = UnifiedToggleInputToggleView()
    private let toolsToolbar = UnifiedToggleInputToolbarView()
    /// Opaque backing behind the toolbar so the card background (not the dark page
    /// background) shows while the toolbar height animates from 0 → 56.
    private let toolbarBackingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(singleUseColor: .unifiedToggleInputCardBackground)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Shadow Layers

    private let expandedShadow0: CALayer = {
        let layer = CALayer()
        layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowRadius = 32
        layer.shadowOffset = CGSize(width: 0, height: -8)
        layer.isHidden = true
        return layer
    }()

    private let expandedShadow1: CALayer = {
        let layer = CALayer()
        layer.shadowColor = UIColor(designSystemColor: .shadowTertiary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.isHidden = true
        return layer
    }()

    // MARK: - Dynamic Colors

    // CALayer colors don't update automatically with trait changes, so we
    // resolve them against the current traitCollection at each use site.

    private var cardShadowColor: CGColor {
        UIColor(designSystemColor: .shadowSecondary).cgColor
    }

    private var expandedBorderColor: CGColor {
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12).cgColor
            : UIColor.black.withAlphaComponent(0.16).cgColor
    }

    private var expandedShadow0Color: CGColor {
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08).cgColor
            : UIColor(designSystemColor: .shadowSecondary).cgColor
    }

    private var expandedShadow1Color: CGColor {
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12).cgColor
            : UIColor(designSystemColor: .shadowTertiary).cgColor
    }

    // MARK: - Constraints

    private var cardTopConstraint: NSLayoutConstraint!
    private var cardLeadingConstraint: NSLayoutConstraint!
    private var cardTrailingConstraint: NSLayoutConstraint!
    private var cardBottomConstraint: NSLayoutConstraint!
    private var cardCollapsedHeightConstraint: NSLayoutConstraint!
    private var toggleTopConstraint: NSLayoutConstraint!
    private var toggleHeightConstraint: NSLayoutConstraint!
    private var inputTopConstraint: NSLayoutConstraint!
    private var toolbarHeightConstraint: NSLayoutConstraint!

    // MARK: - Initialization

    init(handler: UnifiedToggleInputHandler) {
        self.handler = handler
        self.textEntryView = SwitchBarTextEntryView(handler: handler)
        super.init(frame: .zero)
        setupUI()
        setupSubscriptions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(rect: bounds).cgPath
        for shadow in [expandedShadow0, expandedShadow1] {
            shadow.bounds = bounds
            shadow.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shadow.shadowPath = path
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            expandedShadow0.shadowColor = expandedShadow0Color
            expandedShadow1.shadowColor = expandedShadow1Color
            cardView.layer.shadowColor = cardShadowColor
            if isExpanded {
                cardView.layer.borderColor = expandedBorderColor
            }
        }
    }

    // MARK: - First Responder

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textEntryView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        return textEntryView.resignFirstResponder()
    }

    override var isFirstResponder: Bool {
        return textEntryView.isFirstResponder
    }

    // MARK: - Public Methods

    func selectAllText() {
        textEntryView.selectAllText()
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool) {
        handler.setToggleState(mode)
        toggleView.setMode(mode, animated: animated)
        updateToolbarVisibility(for: mode, animated: animated)
        // Keyboard config and placeholder are updated automatically by SwitchBarTextEntryView
        // via its subscription to handler.toggleStatePublisher.
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded

        let toggleHeight = expanded ? Constants.toggleHeight : 0
        let showToolbar = expanded && toggleView.selectedMode == .aiChat
        let hMargin: CGFloat = expanded ? 0 : Constants.cardHorizontalMargin
        let vMargin: CGFloat = expanded ? 0 : Constants.cardVerticalMargin

        textEntryView.isUserInteractionEnabled = expanded
        textEntryView.isExpandable = expanded

        expandedShadow0.isHidden = !expanded
        expandedShadow1.isHidden = !expanded
        if expanded {
            switch cardPosition {
            case .top:
                expandedShadow0.shadowOffset = CGSize(width: 0, height: 8)
                expandedShadow1.shadowOffset = CGSize(width: 0, height: 2)
            case .bottom:
                expandedShadow0.shadowOffset = CGSize(width: 0, height: -8)
                expandedShadow1.shadowOffset = CGSize(width: 0, height: -2)
            }
        }
        cardView.layer.shadowOpacity = expanded ? 0 : 1.0
        cardCollapsedHeightConstraint.isActive = !expanded

        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let expandedCorners: CACornerMask = cardPosition == .top
            ? allCorners
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardView.layer.maskedCorners = expanded ? expandedCorners : allCorners

        cardView.layer.borderWidth = showToolbar ? 0.5 : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor

        let changes = {
            self.cardView.layer.cornerRadius = expanded ? Constants.cardCornerRadiusExpanded : Constants.cardCornerRadiusCollapsed
            self.cardTopConstraint.constant = vMargin
            self.cardLeadingConstraint.constant = hMargin
            self.cardTrailingConstraint.constant = -hMargin
            self.cardBottomConstraint.constant = -vMargin
            self.toggleTopConstraint.constant = expanded ? Constants.toggleTopPadding : 0
            self.toggleHeightConstraint.constant = toggleHeight
            self.inputTopConstraint.constant = expanded ? Constants.toggleBottomPadding : 0
            self.toggleView.alpha = expanded ? 1 : 0
            self.toolbarHeightConstraint.constant = showToolbar ? 56 : 0
            self.toolsToolbar.alpha = showToolbar ? 1 : 0
            self.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: Constants.animationDuration,
                delay: 0,
                options: .curveEaseInOut,
                animations: changes
            )
        } else {
            changes()
        }
    }

    // MARK: - Private

    private func updateToolbarVisibility(for mode: TextEntryMode, animated: Bool) {
        guard isExpanded else { return }

        let showToolbar = mode == .aiChat
        toolbarHeightConstraint.constant = showToolbar ? 56 : 0
        cardView.layer.borderWidth = showToolbar ? 0.5 : 0
        cardView.layer.borderColor = showToolbar ? expandedBorderColor : UIColor.clear.cgColor

        guard animated else {
            toolsToolbar.alpha = showToolbar ? 1 : 0
            layoutIfNeeded()
            return
        }

        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.toolsToolbar.alpha = showToolbar ? 1 : 0
            self.layoutIfNeeded()
            // Trigger a hierarchy-wide layout so sibling views (e.g. the content
            // container constrained to the input bar top) animate in sync.
            self.onNeedsHierarchyLayout?()
        }
    }
}

// MARK: - Setup

private extension UnifiedToggleInputView {

    func setupUI() {
        clipsToBounds = false

        layer.insertSublayer(expandedShadow0, at: 0)
        layer.insertSublayer(expandedShadow1, at: 1)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(singleUseColor: .unifiedToggleInputCardBackground)
        cardView.layer.cornerRadius = Constants.cardCornerRadiusCollapsed
        cardView.layer.shadowColor = cardShadowColor
        cardView.layer.shadowOpacity = 1.0
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12
        cardView.isUserInteractionEnabled = false
        addSubview(cardView)

        toggleView.translatesAutoresizingMaskIntoConstraints = false
        toggleView.alpha = 0
        toggleView.onModeChanged = { [weak self] mode in
            guard let self else { return }
            self.handler.setToggleState(mode)
            self.delegate?.unifiedToggleInputViewDidChangeMode(self, mode: mode)
            if self.isExpanded {
                self.textEntryView.becomeFirstResponder()
            }
        }
        addSubview(toggleView)

        textEntryView.translatesAutoresizingMaskIntoConstraints = false
        textEntryView.isUserInteractionEnabled = false
        textEntryView.isExpandable = false
        textEntryView.placeholderTextColor = UIColor(designSystemColor: .textTertiary)
        addSubview(textEntryView)

        addSubview(toolbarBackingView)

        toolsToolbar.translatesAutoresizingMaskIntoConstraints = false
        toolsToolbar.clipsToBounds = true
        toolsToolbar.alpha = 0
        toolsToolbar.onSubmitTapped = { [weak self] in
            guard let self else { return }
            handler.submitText(handler.currentText)
        }
        addSubview(toolsToolbar)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCollapsedTap))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)

        setupConstraints()
    }

    func setupConstraints() {
        cardTopConstraint = cardView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.cardVerticalMargin)
        cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.cardHorizontalMargin)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.cardHorizontalMargin)
        cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.cardVerticalMargin)
        cardCollapsedHeightConstraint = cardView.heightAnchor.constraint(equalToConstant: Constants.collapsedCardHeight)
        cardCollapsedHeightConstraint.priority = .defaultHigh
        cardCollapsedHeightConstraint.isActive = true
        toggleTopConstraint = toggleView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 0)
        toggleHeightConstraint = toggleView.heightAnchor.constraint(equalToConstant: 0)
        inputTopConstraint = textEntryView.topAnchor.constraint(equalTo: toggleView.bottomAnchor, constant: 0)
        toolbarHeightConstraint = toolsToolbar.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            cardTopConstraint,
            cardLeadingConstraint,
            cardTrailingConstraint,
            cardBottomConstraint,

            toggleTopConstraint,
            toggleView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.toggleHorizontalPadding),
            toggleView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.toggleHorizontalPadding),
            toggleHeightConstraint,

            inputTopConstraint,
            textEntryView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            textEntryView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            toolbarBackingView.topAnchor.constraint(equalTo: toolsToolbar.topAnchor),
            toolbarBackingView.leadingAnchor.constraint(equalTo: toolsToolbar.leadingAnchor),
            toolbarBackingView.trailingAnchor.constraint(equalTo: toolsToolbar.trailingAnchor),
            toolbarBackingView.bottomAnchor.constraint(equalTo: toolsToolbar.bottomAnchor),

            toolsToolbar.topAnchor.constraint(equalTo: textEntryView.bottomAnchor),
            toolsToolbar.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            toolsToolbar.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            toolsToolbar.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            toolbarHeightConstraint,
        ])
    }

    func setupSubscriptions() {
        handler.textSubmissionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] submission in
                guard let self else { return }
                delegate?.unifiedToggleInputViewDidSubmitText(self, text: submission.text, mode: submission.mode)
            }
            .store(in: &cancellables)

        handler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                let hasSubmittableText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                toolsToolbar.isSubmitEnabled = hasSubmittableText
                delegate?.unifiedToggleInputViewDidChangeText(self, text: text)
            }
            .store(in: &cancellables)

        handler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                // Sync the visual toggle indicator and toolbar for programmatic mode changes
                // (e.g. coordinator calling setInputMode). Delegate notification is intentionally
                // omitted here — user-initiated taps fire it synchronously via toggleView.onModeChanged.
                toggleView.setMode(mode, animated: true)
                updateToolbarVisibility(for: mode, animated: true)
            }
            .store(in: &cancellables)

        handler.microphoneButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                delegate?.unifiedToggleInputViewDidTapVoice(self)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Tap Handling (collapsed tap)

extension UnifiedToggleInputView {

    @objc private func handleCollapsedTap() {
        guard !isExpanded else { return }
        delegate?.unifiedToggleInputViewDidTapWhileCollapsed(self)
    }
}
