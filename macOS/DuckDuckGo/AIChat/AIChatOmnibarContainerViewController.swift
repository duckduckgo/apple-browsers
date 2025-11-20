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

final class AIChatOmnibarContainerViewController: NSViewController {

    private let backgroundView = MouseBlockingBackgroundView()
    private let shadowView = ShadowView()
    private let innerBorderView = ColorView(frame: .zero)
    private let containerView = NSView()
    private let submitButton = NSButton()
    let themeManager: ThemeManaging
    let omnibarController: AIChatOmnibarController
    var themeUpdateCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?

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

    private func applyTopClipMask() {
        view.wantsLayer = true
        guard view.bounds.height > 10 else {
            view.layer?.mask = nil
            return
        }
        let mask = CAShapeLayer()
        mask.frame = view.bounds
        let visibleRect = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height - 14)
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
        submitButton.bezelStyle = .regularSquare
        submitButton.isBordered = false
        submitButton.wantsLayer = true
        submitButton.target = self
        submitButton.action = #selector(submitButtonClicked)

        if let arrowImage = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Submit") {
            submitButton.image = arrowImage
            submitButton.imagePosition = .imageOnly
        }

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

            submitButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            submitButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            submitButton.widthAnchor.constraint(equalToConstant: 28),
            submitButton.heightAnchor.constraint(equalToConstant: 28),
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
        frame.size.height -= 11

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
        submitButton.layer?.cornerRadius = 14
        submitButton.contentTintColor = .white

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
