//
//  YouTubeAdBlockPopover.swift
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
import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

// MARK: - YouTubeAdBlockSetting

enum YouTubeAdBlockSetting: String, CaseIterable {
    case alwaysOn
    case disableUntilRelaunch
    case alwaysOff

    var displayName: String {
        switch self {
        case .alwaysOn: return "Always On"
        case .disableUntilRelaunch: return "Disable Until Relaunch"
        case .alwaysOff: return "Always Off"
        }
    }
}

// MARK: - YouTubeAdBlockViewModel

final class YouTubeAdBlockViewModel: ObservableObject {

    private let preferences: YouTubeAdBlockingPreferences
    private let reloadPage: () -> Void

    @Published var setting: YouTubeAdBlockSetting {
        didSet {
            apply(setting)
        }
    }
    @Published var backgroundColor: NSColor = .clear

    init(preferences: YouTubeAdBlockingPreferences = YouTubeAdBlockingPreferences(),
         reloadPage: @escaping () -> Void = {}) {
        self.preferences = preferences
        self.reloadPage = reloadPage
        self.setting = preferences.youTubeAdBlockingEnabled ? .alwaysOn : .alwaysOff
    }

    private func apply(_ setting: YouTubeAdBlockSetting) {
        let wasEnabled = preferences.youTubeAdBlockingEnabled
        switch setting {
        case .alwaysOn:
            preferences.youTubeAdBlockingEnabled = true
        case .alwaysOff:
            preferences.youTubeAdBlockingEnabled = false
        case .disableUntilRelaunch:
            return
        }
        if preferences.youTubeAdBlockingEnabled != wasEnabled {
            reloadPage()
        }
    }
}

// MARK: - YouTubeAdBlockView

struct YouTubeAdBlockView: View {

    @ObservedObject var viewModel: YouTubeAdBlockViewModel

    private enum Layout {
        static let width: CGFloat = 440
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YouTube.com")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            YouTubeAdBlockRowView(currentSetting: $viewModel.setting)
                .background(Color(designSystemColor: .permissionCenterContainerBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(designSystemColor: .lines), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: Layout.width)
        .background(Color(viewModel.backgroundColor))
    }
}

// MARK: - YouTubeAdBlockRowView

struct YouTubeAdBlockRowView: View {

    @Binding var currentSetting: YouTubeAdBlockSetting

    private enum Layout {
        static let iconSize: CGFloat = 24
        static let iconTrailingSpacing: CGFloat = 8
        static var descriptionLeadingInset: CGFloat { iconSize + iconTrailingSpacing }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Layout.iconTrailingSpacing) {
                Image(nsImage: DesignSystemImages.Glyphs.Size24.videoPlayer)
                    .resizable()
                    .frame(width: Layout.iconSize, height: Layout.iconSize)
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text("YouTube Ad Blocking")
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
                    .fixedSize()

                Spacer()

                settingDropdown
            }

            Text("If you encounter video playback issues, disabling Ad Blocking may fix the issue.")
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Layout.descriptionLeadingInset)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var settingDropdown: some View {
        NSPopUpButtonView(selection: $currentSetting) {
            let button = NSPopUpButton()
            button.bezelStyle = .accessoryBarAction
            button.isBordered = true
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)

            for setting in YouTubeAdBlockSetting.allCases {
                let item = button.menu?.addItem(withTitle: setting.displayName, action: nil, keyEquivalent: "")
                item?.representedObject = setting
            }

            return button
        }
        .fixedSize()
    }
}

// MARK: - YouTubeAdBlockViewController

final class YouTubeAdBlockViewController: NSViewController {

    let themeManager: ThemeManaging = NSApp.delegateTyped.themeManager
    var themeUpdateCancellable: AnyCancellable?

    let viewModel: YouTubeAdBlockViewModel
    private var hostingView: NSHostingView<YouTubeAdBlockView>?

    init(viewModel: YouTubeAdBlockViewModel) {
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
        let swiftUIView = YouTubeAdBlockView(viewModel: viewModel)
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

extension YouTubeAdBlockViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        applyBackgroundColor(theme.colorsProvider.popoverBackgroundColor)
    }
}

// MARK: - YouTubeAdBlockPopover

final class YouTubeAdBlockPopover: NSPopover {

    let themeManager: ThemeManaging = NSApp.delegateTyped.themeManager
    var themeUpdateCancellable: AnyCancellable?

    let viewController: YouTubeAdBlockViewController

    init(viewModel: YouTubeAdBlockViewModel) {
        self.viewController = YouTubeAdBlockViewController(viewModel: viewModel)
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

extension YouTubeAdBlockPopover: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        backgroundColor = theme.colorsProvider.popoverBackgroundColor
    }
}
