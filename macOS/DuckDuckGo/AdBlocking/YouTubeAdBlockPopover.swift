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
import Persistence
import SwiftUI
import WebExtensions

// MARK: - YouTubeAdBlockUnavailableTipController

/// Schedules an auto-display of the YouTube Ad Block popover in "unavailable" mode after a
/// short delay, mirroring `QuickFeedbackTipController`'s pattern. The one-shot
/// `youTubeAdBlockUnavailableNoticeShown` flag is checked upfront and recorded only once the
/// popover has actually been shown.
@MainActor
final class YouTubeAdBlockUnavailableTipController {

    private static let showDelay: TimeInterval = 2

    private var scheduledShowWork: DispatchWorkItem?
    private let storage: any KeyedStoring<YouTubeAdBlockingSettings>

    init(storage: (any KeyedStoring<YouTubeAdBlockingSettings>)? = nil) {
        self.storage = if let storage { storage } else { UserDefaults.standard.keyedStoring() }
    }

    /// Schedules the notice to be presented after a short delay. `present` is called once the
    /// delay elapses and is expected to actually show the popover, returning `true` on success.
    /// The one-shot flag is only recorded after a successful presentation, so a failed attempt
    /// (e.g. the anchor view is hidden because the user has the address bar focused) doesn't
    /// burn the chance to surface the notice on the next navigation.
    func scheduleIfNeeded(_ present: @escaping () -> Bool) {
        scheduledShowWork?.cancel()
        guard shouldShow() else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.shouldShow() else { return }
            guard present() else { return }
            var storage = self.storage
            storage.youTubeAdBlockUnavailableNoticeShown = true
        }
        scheduledShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    func cancel() {
        scheduledShowWork?.cancel()
        scheduledShowWork = nil
    }

    private func shouldShow() -> Bool {
        storage.youTubeAdBlockUnavailableNoticeShown != true
    }
}

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
    private let adBlockingAvailability: AdBlockingAvailabilityProviding
    private let reloadPage: () -> Void
    /// Wired by `AddressBarButtonsViewController` after the popover is created so it can close
    /// the popover before presenting the Report Broken Site sheet.
    var sendBreakageReport: () -> Void = {}

    let isRemotelyDisabled: Bool
    @Published var setting: YouTubeAdBlockSetting {
        didSet {
            apply(setting)
        }
    }
    @Published var showBreakageReportBanner: Bool = false
    @Published var backgroundColor: NSColor = .clear

    init(adBlockingAvailability: AdBlockingAvailabilityProviding,
         preferences: YouTubeAdBlockingPreferences? = nil,
         reloadPage: @escaping () -> Void = {}) {
        self.adBlockingAvailability = adBlockingAvailability
        self.preferences = preferences ?? YouTubeAdBlockingPreferences(adBlockingAvailability: adBlockingAvailability)
        self.reloadPage = reloadPage
        self.isRemotelyDisabled = adBlockingAvailability.isRemotelyDisabled

        // Initial dropdown selection mirrors the live state: an active session-scoped
        // "Disable Until Relaunch" override wins over the persisted on/off preference.
        if adBlockingAvailability.isDisabledUntilRelaunch {
            self.setting = .disableUntilRelaunch
        } else if self.preferences.youTubeAdBlockingEnabled {
            self.setting = .alwaysOn
        } else {
            self.setting = .alwaysOff
        }
    }

    func handleSendBreakageReport() {
        sendBreakageReport()
        showBreakageReportBanner = false
    }

    private func apply(_ setting: YouTubeAdBlockSetting) {
        let wasEnabled = preferences.youTubeAdBlockingEnabled
        let wasDisabledUntilRelaunch = adBlockingAvailability.isDisabledUntilRelaunch

        switch setting {
        case .alwaysOn:
            adBlockingAvailability.clearDisableUntilRelaunch()
            preferences.youTubeAdBlockingEnabled = true
        case .alwaysOff:
            adBlockingAvailability.clearDisableUntilRelaunch()
            preferences.youTubeAdBlockingEnabled = false
        case .disableUntilRelaunch:
            adBlockingAvailability.disableUntilRelaunch()
        }

        let stateChanged = preferences.youTubeAdBlockingEnabled != wasEnabled
            || adBlockingAvailability.isDisabledUntilRelaunch != wasDisabledUntilRelaunch
        if stateChanged {
            reloadPage()
            // Show the breakage banner whenever the user has actively disabled ad blocking
            // (either persistently or just for this session) — iOS surfaces a breakage report
            // sheet in both cases too.
            let isDisabled = !preferences.youTubeAdBlockingEnabled
                || adBlockingAvailability.isDisabledUntilRelaunch
            showBreakageReportBanner = isDisabled
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

            if viewModel.isRemotelyDisabled {
                YouTubeAdBlockUnavailableRowView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                YouTubeAdBlockRowView(currentSetting: $viewModel.setting)
                    .background(Color(designSystemColor: .permissionCenterContainerBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(designSystemColor: .lines), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                if viewModel.showBreakageReportBanner {
                    YouTubeAdBlockBreakageReportRowView {
                        viewModel.handleSendBreakageReport()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: Layout.width)
        .background(Color(viewModel.backgroundColor))
    }
}

// MARK: - YouTubeAdBlockRowView

struct YouTubeAdBlockRowView: View {

    @Binding var currentSetting: YouTubeAdBlockSetting

    private enum Layout {
        static let iconSize: CGFloat = 16
        static let iconTrailingSpacing: CGFloat = 8
        static var descriptionLeadingInset: CGFloat { iconSize + iconTrailingSpacing }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Layout.iconTrailingSpacing) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.videoPlayer)
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

// MARK: - YouTubeAdBlockBreakageReportRowView

struct YouTubeAdBlockBreakageReportRowView: View {

    let onSendReport: () -> Void

    private enum Layout {
        static let iconSize: CGFloat = 16
        static let iconTrailingSpacing: CGFloat = 8
        static var descriptionLeadingInset: CGFloat { iconSize + iconTrailingSpacing }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Layout.iconTrailingSpacing) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.feedbackAlert)
                    .resizable()
                    .frame(width: Layout.iconSize, height: Layout.iconSize)
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text("YouTube Ad Blocking not working?")
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
                    .fixedSize()

                Spacer()

                Button(action: onSendReport) {
                    Text("Send Report")
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .permissionReloadButtonText))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(designSystemColor: .permissionReloadButtonBackground))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(designSystemColor: .lines), lineWidth: 0.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }

            Text("Send an anonymous breakage report to DuckDuckGo. Help make Ad Blocking better for everyone!")
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Layout.descriptionLeadingInset)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(designSystemColor: .permissionWarningBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(designSystemColor: .lines), lineWidth: 1)
                )
        )
    }
}

// MARK: - YouTubeAdBlockUnavailableRowView

struct YouTubeAdBlockUnavailableRowView: View {

    private enum Layout {
        static let iconSize: CGFloat = 16
        static let iconTrailingSpacing: CGFloat = 8
        static var descriptionLeadingInset: CGFloat { iconSize + iconTrailingSpacing }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Layout.iconTrailingSpacing) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.videoPlayer)
                    .resizable()
                    .frame(width: Layout.iconSize, height: Layout.iconSize)
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text("YouTube Ad Block Unavailable")
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }

            Text("Ad Blocking has been affected by recent changes to YouTube. We're working to fix these issues and appreciate your understanding")
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Layout.descriptionLeadingInset)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(designSystemColor: .permissionWarningBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(designSystemColor: .lines), lineWidth: 1)
                )
        )
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
        let hostingView = NSHostingView(rootView: YouTubeAdBlockView(viewModel: viewModel))
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
