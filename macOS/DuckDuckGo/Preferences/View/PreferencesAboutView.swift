//
//  PreferencesAboutView.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AppUpdaterShared
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

fileprivate extension Font {
    static let companyName: Font = .title
    static let privacySimplified: Font = .title3.weight(.semibold)
}

extension Preferences {

    struct AboutView: View {
        @ObservedObject var model: AboutPreferences
        @State private var areAutomaticUpdatesEnabled: Bool = true
        @State private var isCustomFeedWarningDismissed = false

        var autoUpdatesEnabled: Bool {
            let buildType = StandardApplicationBuildType()
            if buildType.isSparkleBuild {
                if buildType.isDebugBuild {
                    return NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG)
                } else if buildType.isReviewBuild {
                    return NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInREVIEW)
                } else {
                    return true
                }
            } else {
                return false
            }
        }

        var body: some View {
            PreferencePane {
                VStack(alignment: .leading) {
                    TextMenuTitle(UserText.aboutDuckDuckGo)

                    if let warning = model.osSupportWarning {
                        UnsupportedDeviceInfoBox(warning: warning)
                            .padding(.top, 10)
                    }

                    AboutContentSection(model: model)

                    let buildType = StandardApplicationBuildType()
                    if buildType.isSparkleBuild {
                        if model.shouldHideManualUpdateOption {
                            UpdateInfoMessage()
                                .padding(.top, 4)
                        } else {
                            UpdatesSection(areAutomaticUpdatesEnabled: $areAutomaticUpdatesEnabled, model: model)
                        }

                        if buildType.isDebugBuild || buildType.isReviewBuild {
                            if !isCustomFeedWarningDismissed {
                                Spacer(minLength: 20)
                                customFeedURLWarning(onDismiss: { isCustomFeedWarningDismissed = true })
                            }
                        }
                    } else if buildType.isAppStoreBuild {
                        UpdateInfoMessage()
                            .padding(.top, 4)
                    }
                }
            }.task {
                if autoUpdatesEnabled {
                    model.checkForUpdate(userInitiated: false)
                }
            }
            .onChange(of: model.featureFlagOverrideToggle) { _ in
                // Intentional no-op
                // This will cause SwiftUI to re-evaluate the view body and
                // redraw when one of the relevant feature flag ovverides
                // is toggled.
            }
        }

        /// Warning banner shown when a custom Sparkle feed URL is configured.
        ///
        /// This reminder helps developers avoid accidentally forgetting they have a custom
        /// feed URL set, which could lead to confusion when testing updates or when the
        /// app doesn't behave as expected with production updates.
        @ViewBuilder
        private func customFeedURLWarning(onDismiss: @escaping () -> Void) -> some View {
            if let customURL = model.customFeedURL {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Updates Are Using a Custom Feed URL")
                            .fontWeight(.semibold)
                        Text(verbatim: customURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(verbatim: "To disable, go to Debug → Updates → Reset feed URL to default")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(8)
            }
        }
    }

    struct AboutContentSection: View {
        @ObservedObject var model: AboutPreferences

        var body: some View {
            PreferencePaneSection {
                if #available(macOS 13.0, *) {
                    ViewThatFits(in: .horizontal) {
                        horizontalPageLogo
                        verticalPageLogo
                    }
                } else {
                    horizontalPageLogo
                }

                TextButton(UserText.moreAt(url: model.displayableAboutURL)) {
                    model.openNewTab(with: .aboutDuckDuckGo)
                }

                TextButton(UserText.privacyPolicy) {
                    model.openNewTab(with: .privacyPolicy)
                }

                TextButton(UserText.termsOfService) {
                    model.openNewTab(with: .termsOfService)
                }

                Button(UserText.sendFeedback) {
                    model.openFeedbackForm()
                }
                .padding(.top, 4)
            }
            .onAppear {
                model.subscribeToUpdateInfoIfNeeded()
            }
        }

        private var rightColumnContent: some View {
            Group {
                HStack(spacing: 8) {
                    Text(UserText.duckDuckGo)
                        .font(.companyName)
                    if model.appVersionModel.shouldDisplayPrereleaseLabel {
                        Text(model.appVersionModel.prereleaseLabel)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.betaLabelBackground)
                            )
                            .foregroundColor(Color.betaLabelForeground)
                    }
                }

                Text(UserText.duckduckgoTagline).font(.privacySimplified)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                HStack {
                    statusIcon.frame(width: 16, height: 16)
                    VStack(alignment: .leading) {
                        versionText
                        lastCheckedText
                    }
                }
                .padding(.bottom, 4)

                updateButton
            }
        }

        private var horizontalPageLogo: some View {
            HStack(alignment: .top) {
                logoImage
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    rightColumnContent
                }
                .padding(.top, 10)
            }
            .padding(.bottom, 8)
        }

        private var verticalPageLogo: some View {
            VStack(alignment: .leading) {
                logoImage
                VStack(alignment: .leading, spacing: 8) {
                    rightColumnContent
                }
                .padding(.top, 10)
            }
            .padding(.bottom, 8)
        }

        @ViewBuilder
        private var logoImage: some View {
            if StandardApplicationBuildType().isAlphaBuild {
                Image(.aboutPageLogoAlpha)
            } else {
                Image(.aboutPageLogo)
            }
        }

        private var hasPendingUpdate: Bool {
            model.updateController?.hasPendingUpdate == true
        }
        private var hasCriticalUpdate: Bool {
            model.updateController?.latestUpdate?.type == .critical
        }

        @ViewBuilder
        private var versionText: some View {
            HStack(spacing: 0) {
                Text(model.appVersionModel.versionLabel)
                    .contextMenu(ContextMenu(menuItems: {
                        Button(UserText.copy, action: {
                            model.copy(model.appVersionModel.versionLabel)
                        })
                    }))

                // Only show update status if feature flag is enabled
                if model.shouldShowUpdateStatus {
                    switch model.updateState {
                    case .upToDate:
                        Text(" — " + UserText.upToDate)
                    case .updateCycle(let progress):
                        if hasPendingUpdate {
                            if hasCriticalUpdate {
                                Text(" — " + UserText.newerCriticalUpdateAvailable)
                            } else {
                                Text(" — " + UserText.newerVersionAvailable)
                            }
                        } else {
                            text(for: progress)
                        }
                    }
                }
            }
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .percent
            formatter.maximumFractionDigits = 0
            return formatter
        }

        @ViewBuilder
        private func text(for progress: UpdateCycleProgress) -> some View {
            switch progress {
            case .updateCycleDidStart:
                Text(" — " + UserText.checkingForUpdate)
            case .downloadDidStart:
                Text(" — " + String(format: UserText.downloadingUpdate, ""))
            case .downloading(let percentage):
                Text(" — " + String(format: UserText.downloadingUpdate,
                                    formatter.string(from: NSNumber(value: percentage)) ?? ""))
            case .extractionDidStart, .extracting, .readyToInstallAndRelaunch, .installationDidStart, .installing:
                Text(" — " + UserText.preparingUpdate)
            case .updaterError:
                Text(" — " + UserText.updateFailed)
            case .updateCycleNotStarted, .updateCycleDone:
                EmptyView()
            }
        }

        @ViewBuilder
        private var statusIcon: some View {
            // Only show status icon if feature flag is enabled
            if model.shouldShowUpdateStatus {
                switch model.updateState {
                case .upToDate:
                    Image(nsImage: .check)
                        .foregroundColor(.green)
                case .updateCycle(let progress):
                    if hasPendingUpdate {
                        if hasCriticalUpdate {
                            Image(nsImage: .criticalUpdateNotificationInfo)
                                .foregroundColor(.red)
                        } else {
                            Image(nsImage: .updateNotificationInfo)
                                .foregroundColor(.blue)
                        }
                    } else if progress.isFailed {
                        Image(nsImage: .criticalUpdateNotificationInfo)
                            .foregroundColor(.red)
                    } else {
                        if #available(macOS 13.0, *) {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            ProgressView()
                        }
                    }
                }
            } else {
                // Empty view when feature flag is off
                EmptyView()
            }
        }

        @ViewBuilder
        private var lastCheckedText: some View {
            // Only show last checked text if feature flag is enabled
            if model.shouldShowUpdateStatus {
                let lastChecked = model.updateController?.updateProgress.isIdle == true ? lastCheckedFormattedDate(model.lastUpdateCheckDate) : "-"
                Text("\(UserText.lastChecked): \(lastChecked)")
                    .foregroundColor(.secondary)
            }
        }

        private func lastCheckedFormattedDate(_ date: Date?) -> String {
            guard let date = date else { return "-" }

            let relativeDateFormatter = RelativeDateTimeFormatter()
            relativeDateFormatter.dateTimeStyle = .named

            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short

            let relativeDate = relativeDateFormatter.localizedString(for: date, relativeTo: Date())

            return relativeDate
        }

        @ViewBuilder
        private var updateButton: some View {
            if model.shouldShowUpdateStatus {
                let configuration = model.updateButtonConfiguration

                Button(configuration.title, action: configuration.action)
                    .buttonStyle(UpdateButtonStyle(enabled: configuration.enabled))
                    .disabled(!configuration.enabled)
            } else {
                // Feature flag is OFF - show simple App Store button
                Button(UserText.checkForUpdate) {
                    model.checkForAppStoreUpdate()
                }
                .buttonStyle(UpdateButtonStyle(enabled: true))
            }
        }
    }

    struct UpdateInfoMessage: View {
        private let buildType: ApplicationBuildType

        init(buildType: ApplicationBuildType = StandardApplicationBuildType()) {
            self.buildType = buildType
        }

        var body: some View {
            if buildType.isSparkleBuild {
                TextMenuItemCaption(UserText.aboutUpdateInfoSparkle)
            } else if buildType.isAppStoreBuild {
                let linkText = UserText.aboutUpdateInfoAppStoreLink
                let menuText = UserText.aboutUpdateInfoAppStoreMenu
                let settingsText = UserText.aboutUpdateInfoAppStoreSettings
                let fullText = String(format: UserText.aboutUpdateInfoAppStore, linkText, menuText, settingsText)
                HStack(spacing: 0) {
                    if #available(macOS 12.0, *) {
                        Text(appStoreAttributedText(fullText: fullText, linkText: linkText))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        NSAttributedTextView(attributedString: appStoreLegacyAttributedText(fullText: fullText, linkText: linkText))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(Color(.greyText))
            }
        }

        private static let boldWords = [
            UserText.aboutUpdateInfoAppStoreLink,
            UserText.aboutUpdateInfoAppStoreMenu,
            UserText.aboutUpdateInfoAppStoreSettings
        ]

        @available(macOS 12, *)
        private func appStoreAttributedText(fullText: String, linkText: String) -> AttributedString {
            var attributed = AttributedString(fullText)
            if let range = attributed.range(of: linkText) {
                attributed[range].link = .appStore
            }
            for word in Self.boldWords {
                if let range = attributed.range(of: word) {
                    attributed[range].inlinePresentationIntent = .stronglyEmphasized
                }
            }
            return attributed
        }

        private func appStoreLegacyAttributedText(fullText: String, linkText: String) -> NSAttributedString {
            let attributedString = NSMutableAttributedString(string: fullText)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 0
            paragraphStyle.paragraphSpacing = 0

            let defaultAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor(Color(.greyText)),
                .paragraphStyle: paragraphStyle
            ]
            attributedString.addAttributes(defaultAttributes, range: NSRange(location: 0, length: attributedString.length))

            if let range = fullText.range(of: linkText) {
                let nsRange = NSRange(range, in: fullText)
                attributedString.addAttribute(.link, value: URL.appStore, range: nsRange)
                attributedString.addAttribute(.foregroundColor, value: NSColor.linkColor, range: nsRange)
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
            }

            let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            for word in Self.boldWords {
                if let range = fullText.range(of: word) {
                    attributedString.addAttribute(.font, value: boldFont, range: NSRange(range, in: fullText))
                }
            }

            return attributedString
        }
    }

    struct UpdatesSection: View {
        @Binding var areAutomaticUpdatesEnabled: Bool
        @ObservedObject var model: AboutPreferences

        var body: some View {
            PreferencePaneSection(UserText.browserUpdatesTitle) {
                PreferencePaneSubSection {
                    Picker(selection: $areAutomaticUpdatesEnabled, content: {
                        Text(UserText.automaticUpdates).tag(true)
                            .padding(.bottom, 4).accessibilityIdentifier("PreferencesAboutView.automaticUpdatesPicker.automatically")
                        Text(UserText.manualUpdates).tag(false)
                            .accessibilityIdentifier("PreferencesAboutView.automaticUpdatesPicker.manually")
                    }, label: {})
                    .pickerStyle(.radioGroup)
                    .offset(x: PreferencesUI_macOS.Const.pickerHorizontalOffset)
                    .accessibilityIdentifier("PreferencesAboutView.automaticUpdatesPicker")
                    .onChange(of: areAutomaticUpdatesEnabled) { newValue in
                        model.areAutomaticUpdatesEnabled = newValue
                    }
                    .onAppear {
                        areAutomaticUpdatesEnabled = model.areAutomaticUpdatesEnabled
                    }
                }
            }
        }
    }

    struct UnsupportedDeviceInfoBox: View {

        static let softwareUpdateURL = URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")!

        var warning: OSSupportWarning

        private var osVersion: String {
            return "\(ProcessInfo.processInfo.operatingSystemVersion)"
        }

        private var versionString: String {
            switch warning {
            case .unsupported(let versionString),
                    .willDropSupportSoon(let versionString):
                return versionString
            }
        }

        private var versionText: String {
            switch warning {
            case .unsupported:
                return UserText.aboutUnsupportedDeviceInfo1
            case .willDropSupportSoon:
                return UserText.aboutWillSoonBeUnsupportedDeviceInfo1
            }
        }

        private var combinedText: String {
            switch warning {
            case .unsupported(let minVersion):
                return UserText.aboutUnsupportedDeviceInfo2(version: minVersion)
            case .willDropSupportSoon(let upcomingMinVersion):
                return UserText.aboutWillSoonBeUnsupportedDeviceInfo2(version: upcomingMinVersion)
            }
        }

        var body: some View {
            let image = Image(.alertColor16)
                .resizable()
                .frame(width: 16, height: 16)
                .padding(.trailing, 4)

            let versionText = Text(versionText)

            let contentView: some View = HStack(alignment: .center, spacing: 0) {
                if #available(macOS 12.0, *) {
                    Text(combinedTextAttributedAttributed)
                } else {
                    NSAttributedTextView(attributedString: legacyCombinedTextAttributed)
                }

                // Added to prevent bouncy animation when resizing the parent view
                // caused by the text width being a bit jumpy.
                Spacer()
            }

            return HStack(alignment: .top) {
                image
                VStack(alignment: .leading, spacing: 12) {
                    versionText
                    contentView
                }
            }
            .padding()
            .background(Color.unsupportedOSWarning)
            .cornerRadius(8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 320, maxWidth: 510)
        }

        @available(macOS 12, *)
        private var combinedTextAttributedAttributed: AttributedString {
            var instructions = AttributedString(combinedText)
            if let range = instructions.range(of: "macOS \(versionString)") {
                instructions[range].link = Self.softwareUpdateURL
            }
            return instructions
        }

        private var legacyCombinedTextAttributed: NSAttributedString {
            let fullText = combinedText
            let attributedString = NSMutableAttributedString(string: fullText)

            // Create paragraph style for consistent formatting
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 0
            paragraphStyle.paragraphSpacing = 0

            // Apply default text styling to match SwiftUI Text
            let defaultAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            attributedString.addAttributes(defaultAttributes, range: NSRange(location: 0, length: attributedString.length))

            // Find the version string to make it clickable
            let versionText = "macOS \(versionString)"
            if let range = fullText.range(of: versionText) {
                let nsRange = NSRange(range, in: fullText)
                attributedString.addAttribute(.link, value: Self.softwareUpdateURL, range: nsRange)
                attributedString.addAttribute(.foregroundColor, value: NSColor.linkColor, range: nsRange)
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
            }

            return attributedString
        }
    }
}

struct UpdateButtonStyle: ButtonStyle {

    public let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public func makeBody(configuration: Self.Configuration) -> some View {

        let enabledBackgroundColor = configuration.isPressed ? Color(NSColor.controlAccentColor).opacity(0.5) : Color(NSColor.controlAccentColor)
        let disabledBackgroundColor = Color.gray.opacity(0.1)
        let labelColor = enabled ? Color.white : Color.primary.opacity(0.3)

        configuration.label
            .lineLimit(1)
            .frame(height: 28)
            .padding(.horizontal, 24)
            .background(enabled ? enabledBackgroundColor : disabledBackgroundColor)
            .foregroundColor(labelColor)
            .cornerRadius(8)
    }

}
