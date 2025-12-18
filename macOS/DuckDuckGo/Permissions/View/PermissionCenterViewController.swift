//
//  PermissionCenterViewController.swift
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
import Combine
import DesignResourcesKit
import SwiftUI

final class PermissionCenterViewController: NSViewController {

    let themeManager: ThemeManaging = NSApp.delegateTyped.themeManager
    var themeUpdateCancellable: AnyCancellable?

    let viewModel: PermissionCenterViewModel
    private var hostingView: NSHostingView<PermissionCenterView>?

    init(viewModel: PermissionCenterViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let backgroundView = NSView()
        backgroundView.wantsLayer = true
        view = backgroundView
        applyBackgroundColor(themeManager.theme.colorsProvider.popoverBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHostingView()
        subscribeToThemeChanges()
    }

    private func setupHostingView() {
        let swiftUIView = PermissionCenterView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.hostingView = hostingView
    }

    private func applyBackgroundColor(_ color: NSColor) {
        view.layer?.backgroundColor = color.cgColor
        viewModel.backgroundColor = color
    }
}

// MARK: - ThemeUpdateListening

extension PermissionCenterViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        applyBackgroundColor(theme.colorsProvider.popoverBackgroundColor)
    }
}

// MARK: - PermissionCenterPopover

final class PermissionCenterPopover: NSPopover {

    let themeManager: ThemeManaging = NSApp.delegateTyped.themeManager
    var themeUpdateCancellable: AnyCancellable?

    let viewController: PermissionCenterViewController

    init(viewModel: PermissionCenterViewModel) {
        self.viewController = PermissionCenterViewController(viewModel: viewModel)
        super.init()

        self.contentViewController = viewController
        self.behavior = .transient
        self.animates = true

        subscribeToThemeChanges()
        applyThemeStyle(theme: themeManager.theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - ThemeUpdateListening

extension PermissionCenterPopover: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        backgroundColor = theme.colorsProvider.popoverBackgroundColor
    }
}
