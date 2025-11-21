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
        if mustSkipDisplayingTitle(title: title, url: url, previousURL: sourceURL) {
            return
        }

        let previousTitle = titleTextField.stringValue
        let requiresInitialAlpha = mustApplyInitialAlpha(targetURL: url, previousURL: sourceURL)

        titleTextField.stringValue = title
        previousTextField.stringValue = previousTitle
        sourceURL = url

        if requiresInitialAlpha {
            titleTextField.alphaValue = ColorAnimation.initialAlpha(url: url)
        }

        guard animated, mustAnimateTitleTransition(title: title, previousTitle: previousTitle) else {
            return
        }

        transitionToLatestTitle(fadeInTitle: requiresInitialAlpha)
    }

    /// Refreshes the Title Color
    /// - Important:
    ///     `alphaValue` is initially set when a new Title is rendered. In order to avoid flickering, we'll skip applying a lower Alpha value
    ///     We'll also account for the NTP scenario.
    ///
    func refreshTitleColorIfNeeded(rendered: Bool, url: URL?) {
        let fromAlpha = titleTextField.alphaValue
        let toAlpha = ColorAnimation.titleAlpha(url: url, rendered: rendered)

        guard mustUpdateTitleAlpha(fromAlpha: fromAlpha, toAlpha: toAlpha, url: url) else {
            return
        }

        titleTextField.alphaValue = toAlpha
        transitionTitleToAlpha(toAlpha: toAlpha, fromAlpha: fromAlpha)
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

    func mustSkipDisplayingTitle(title: String, url: URL?, previousURL: URL?) -> Bool {
        previousURL?.host == url?.host && url?.suggestedTitlePlaceholder == title
    }

    func mustAnimateTitleTransition(title: String, previousTitle: String) -> Bool {
        title != previousTitle && previousTitle.isEmpty == false
    }

    func mustApplyInitialAlpha(targetURL: URL?, previousURL: URL?) -> Bool {
        targetURL?.isNTP == true || targetURL?.host?.dropSubdomain() != previousURL?.host?.dropSubdomain()
    }

    func mustUpdateTitleAlpha(fromAlpha: CGFloat, toAlpha: CGFloat, url: URL?) -> Bool {
        toAlpha > fromAlpha && url?.isNTP == false
    }
}

private extension TabTitleView {

    func transitionToLatestTitle(fadeInTitle: Bool) {
        CATransaction.begin()

        dismissPreviousTitle()
        presentCurrentTitle()

        if fadeInTitle {
            transitionTitleToAlpha(toAlpha: titleTextField.alphaValue, fromAlpha: 0)
        }

        CATransaction.commit()
    }

    func dismissPreviousTitle() {
        guard let previousTitleLayer = previousTextField.layer else {
            return
        }

        let fromAlpha = Float(titleTextField.alphaValue)
        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [
            CASpringAnimation.buildFadeOutAnimation(duration: TitleAnimation.duration, fromAlpha: fromAlpha),
            CASpringAnimation.buildTranslationXAnimation(duration: TitleAnimation.duration, fromValue: TitleAnimation.slidingOutStartX, toValue: TitleAnimation.slidingOutLastX)
        ]

        previousTitleLayer.opacity = 0
        previousTitleLayer.add(animationGroup, forKey: TitleAnimation.fadeAndSlideOutKey)
    }

    func presentCurrentTitle() {
        guard let titleLayer = titleTextField.layer else {
            return
        }

        let slideAnimation = CASpringAnimation.buildTranslationXAnimation(duration: TitleAnimation.duration, fromValue: TitleAnimation.slidingInStartX, toValue: TitleAnimation.slidingInLastX)
        titleLayer.add(slideAnimation, forKey: TitleAnimation.slideInKey)
    }

    func transitionTitleToAlpha(toAlpha: CGFloat, fromAlpha: CGFloat) {
        guard let titleLayer = titleTextField.layer else {
            return
        }

        let animation = CASpringAnimation.buildFadeAnimation(duration: TitleAnimation.duration, fromValue: Float(fromAlpha), toValue: Float(toAlpha))
        titleLayer.add(animation, forKey: TitleAnimation.alphaKey)
    }
}

private enum TitleAnimation {
    static let fadeAndSlideOutKey = "fadeOutAndSlide"
    static let slideInKey = "slideIn"
    static let alphaKey = "alpha"
    static let duration: TimeInterval = 0.2
    static let slidingOutStartX = CGFloat(0)
    static let slidingOutLastX = CGFloat(-4)
    static let slidingInStartX = CGFloat(-4)
    static let slidingInLastX = CGFloat(0)
}

private enum ColorAnimation {
    static let specialTitleAlpha: CGFloat = 0.4
    static let loadingTitleAlpha: CGFloat = 0.6
    static let completeTitleAlpha: CGFloat = 1

    static func initialAlpha(url: URL?) -> CGFloat {
        titleAlpha(url: url, rendered: false)
    }

    static func titleAlpha(url: URL?, rendered: Bool) -> CGFloat {
        if let url, url.isNTP {
            return specialTitleAlpha
        }

        return rendered ? completeTitleAlpha : loadingTitleAlpha
    }
}
