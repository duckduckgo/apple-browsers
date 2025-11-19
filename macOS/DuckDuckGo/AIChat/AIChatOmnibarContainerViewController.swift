//
//  AIChatOmnibarContainerViewController.swift
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

import Cocoa
import QuartzCore
import Combine
import DesignResourcesKitIcons

final class AIChatOmnibarContainerViewController: NSViewController {

    private enum Constants {
        static let clipMaskBottomOffset: CGFloat = 14
        static let shadowOverlapHeight: CGFloat = 11
        static let submitButtonSize: CGFloat = 28
        static let submitButtonCornerRadius: CGFloat = 14
        static let submitButtonTrailingInset: CGFloat = 13
        static let submitButtonBottomInset: CGFloat = 13
    }

    private let backgroundView = MouseBlockingBackgroundView()
    private let shadowView = ShadowView()
    private let innerBorderView = ColorView(frame: .zero)
    private let containerView = NSView()
    private let submitButton = MouseOverButton()
    let themeManager: ThemeManaging
    let omnibarController: AIChatOmnibarController
    var themeUpdateCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var textChangeCancellable: AnyCancellable?

    required init?(coder: NSCoder) {
        fatalError("AIChatOmnibarContainerViewController: Bad initializer")
    }

    required init(themeManager: ThemeManaging, omnibarController: AIChatOmnibarController) {
        self.themeManager = themeManager
        self.omnibarController = omnibarController

        super.init(nibName: nil, bundle: nil)
    }

    override func loadView() {
        view = MouseOverView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        subscribeToThemeChanges()
        subscribeToTextChanges()
        applyThemeStyle()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyTopClipMask()
        layoutShadowView()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        subscribeToViewAppearanceChanges()
    }

    private func subscribeToViewAppearanceChanges() {
        appearanceCancellable = view.publisher(for: \.effectiveAppearance)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyThemeStyle()
            }
    }

    private func subscribeToTextChanges() {
        textChangeCancellable = omnibarController.$currentText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.updateSubmitButtonVisibility(for: text)
            }
    }

    private func updateSubmitButtonVisibility(for text: String) {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        submitButton.isHidden = !hasText
    }

    private func applyTopClipMask() {
        view.wantsLayer = true
        guard view.bounds.height > 10 else {
            view.layer?.mask = nil
            return
        }
        let mask = CAShapeLayer()
        mask.frame = view.bounds
        let visibleRect = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height - Constants.clipMaskBottomOffset)
        mask.path = CGPath(rect: visibleRect, transform: nil)
        view.layer?.mask = mask
    }

    private func setupUI() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.borderWidth = 1
        backgroundView.borderColor = NSColor.black.withAlphaComponent(0.2)
        view.addSubview(backgroundView)

        innerBorderView.translatesAutoresizingMaskIntoConstraints = false
        innerBorderView.borderWidth = 1
        backgroundView.addSubview(innerBorderView)

        shadowView.shadowColor = .suggestionsShadow
        shadowView.shadowOpacity = 1
        shadowView.shadowOffset = CGSize(width: 0, height: 0)
        shadowView.shadowRadius = 20
        shadowView.shadowSides = [.left, .right, .bottom]

        containerView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(containerView)

        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.title = ""
        submitButton.bezelStyle = .shadowlessSquare
        submitButton.isBordered = false
        submitButton.wantsLayer = true
        submitButton.target = self
        submitButton.action = #selector(submitButtonClicked)

        submitButton.image = DesignSystemImages.Glyphs.Size12.arrowRight
        submitButton.imagePosition = .imageOnly
        submitButton.isHidden = true  // Initially hidden until text is entered
        containerView.addSubview(submitButton)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            innerBorderView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 1),
            innerBorderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 1),
            innerBorderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -1),
            innerBorderView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -1),

            containerView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            submitButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.submitButtonTrailingInset),
            submitButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Constants.submitButtonBottomInset),
            submitButton.widthAnchor.constraint(equalToConstant: Constants.submitButtonSize),
            submitButton.heightAnchor.constraint(equalToConstant: Constants.submitButtonSize),
        ])

        applyTheme(theme: themeManager.theme)
    }

    /// Starts event monitoring. Call this when the view controller becomes visible.
    func startEventMonitoring() {
        backgroundView.startListening()
        addShadowToWindow()
    }

    /// Stops event monitoring. Call this when the view controller is about to be dismissed.
    func cleanup() {
        backgroundView.stopListening()
        shadowView.removeFromSuperview()
    }

    private func addShadowToWindow() {
        guard shadowView.superview == nil else { return }
        view.window?.contentView?.addSubview(shadowView)
        layoutShadowView()
    }

    private func layoutShadowView() {
        guard let superview = shadowView.superview else { return }

        let winFrame = view.convert(view.bounds, to: nil)
        var frame = superview.convert(winFrame, from: nil)

        /// Do not overlap shadow of main address bar
        frame.size.height -= Constants.shadowOverlapHeight

        shadowView.frame = frame
    }

    @objc private func submitButtonClicked() {
        omnibarController.submit()
    }

    private func applyTheme(theme: ThemeStyleProviding) {
        let barStyleProvider = theme.addressBarStyleProvider
        let colorsProvider = theme.colorsProvider

        backgroundView.backgroundColor = colorsProvider.activeAddressBarBackgroundColor
        backgroundView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadius
        backgroundView.layer?.masksToBounds = false  // Don't clip subviews - important for hit testing

        if let borderColor = NSColor(named: "AddressBarBorderColor") {
            backgroundView.borderColor = borderColor
        }

        submitButton.layer?.backgroundColor = colorsProvider.accentPrimaryColor.cgColor
        submitButton.layer?.cornerRadius = Constants.submitButtonCornerRadius

        submitButton.normalTintColor = .white
        submitButton.mouseOverTintColor = NSColor(designSystemColor: .buttonsPrimaryText).withAlphaComponent(0.8)

        innerBorderView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadius
        innerBorderView.borderColor = NSColor(named: "AddressBarInnerBorderColor")
        innerBorderView.backgroundColor = NSColor.clear
        innerBorderView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadius

        shadowView.shadowRadius = barStyleProvider.suggestionShadowRadius
        shadowView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadius
    }
}

extension AIChatOmnibarContainerViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        applyTheme(theme: theme)
    }
}
