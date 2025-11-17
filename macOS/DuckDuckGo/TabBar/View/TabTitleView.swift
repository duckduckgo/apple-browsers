//
//  TabTitleView.swift
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

import AppKit

final class TabTitleView: NSView {

    private lazy var titleTextField: NSTextField = buildTitleTextField()
    private lazy var previousTextField: NSTextField = buildTitleTextField()
    private(set) var sourceURL: URL?

    var title: String {
        get {
            titleTextField.stringValue
        }
        set {
            titleTextField.stringValue = newValue
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupSubviews()
        setupLayer()
        setupConstraints()
        setupTextFields()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension TabTitleView {

    /// Displays the specified Title **Unless** the following conditions are met
    ///     1. We're already displaying a Title for the same URL
    ///     2. The new Title is the "Suggested Placeholder" (Host minus the `www` prefix, and no schema)
    ///
    /// This exit mechanism is meant to handle Page Reload scenarios, in which we're already rendering a Title, and we'd wanna
    /// avoid animating the Placeholder.
    ///
    func displayTitleIfNeeded(title: String, url: URL?, animated: Bool = true) {
        if shouldSkipApplyingTitle(title: title, url: url) {
            return
        }

        let previousTitle = titleTextField.stringValue
        titleTextField.stringValue = title
        sourceURL = url

        guard animated, title != previousTitle, previousTitle.isEmpty == false else {
            return
        }

        transitionToLatestTitle(previousTitle: previousTitle)
    }

    func reset() {
        titleTextField.stringValue = ""
        previousTextField.stringValue = ""
        sourceURL = nil
    }
}

private extension TabTitleView {

    func setupSubviews() {
        addSubview(previousTextField)
        addSubview(titleTextField)
    }

    func setupLayer() {
        wantsLayer = true
    }

    func setupConstraints() {
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleTextField.topAnchor.constraint(equalTo: topAnchor),
            titleTextField.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleTextField.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        previousTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previousTextField.topAnchor.constraint(equalTo: topAnchor),
            previousTextField.bottomAnchor.constraint(equalTo: bottomAnchor),
            previousTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            previousTextField.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func setupTextFields() {
        titleTextField.textColor = .labelColor
        previousTextField.textColor = .labelColor.withAlphaComponent(0.6)
    }

    func buildTitleTextField() -> NSTextField {
        let textField = NSTextField()
        textField.wantsLayer = true
        textField.isEditable = false
        textField.alignment = .left
        textField.drawsBackground = false
        textField.isBordered = false
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byClipping
        return textField
    }
}

private extension TabTitleView {

    func shouldSkipApplyingTitle(title: String, url: URL?) -> Bool {
        sourceURL == url && url?.suggestedTitlePlaceholder == title
    }

    func transitionToLatestTitle(previousTitle: String) {
        CATransaction.begin()

        dismissPreviousTitle(previousTitle)
        presentCurrentTitle()

        CATransaction.commit()
    }

    func dismissPreviousTitle(_ previousTitle: String) {
        guard let previousTitleLayer = previousTextField.layer else {
            return
        }

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [
            CASpringAnimation.buildFadeOutAnimation(duration: TitleAnimation.duration),
            CASpringAnimation.buildTranslationXAnimation(duration: TitleAnimation.duration, fromValue: TitleAnimation.slidingOutStartX, toValue: TitleAnimation.slidingOutLastX)
        ]

        previousTextField.stringValue = previousTitle
        previousTitleLayer.opacity = 0
        previousTitleLayer.add(animationGroup, forKey: TitleAnimation.fadeAndSlideOutKey)
    }

    func presentCurrentTitle() {
        guard let titleLayer = titleTextField.layer else {
            return
        }

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [
            CASpringAnimation.buildFadeInAnimation(duration: TitleAnimation.duration),
            CASpringAnimation.buildTranslationXAnimation(duration: TitleAnimation.duration, fromValue: TitleAnimation.slidingInStartX, toValue: TitleAnimation.slidingInLastX)
        ]

        titleLayer.add(animationGroup, forKey: TitleAnimation.slideInKey)
    }
}

private enum TitleAnimation {
    static let fadeAndSlideOutKey = "fadeOutAndSlide"
    static let slideInKey = "slideIn"
    static let duration: TimeInterval = 0.15
    static let slidingOutStartX = CGFloat(0)
    static let slidingOutLastX = CGFloat(-4)
    static let slidingInStartX = CGFloat(-4)
    static let slidingInLastX = CGFloat(0)
}
