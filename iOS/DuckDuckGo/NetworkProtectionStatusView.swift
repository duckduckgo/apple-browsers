//
//  NetworkProtectionStatusView.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import Lottie
import Networking
import SwiftUI
import TipKit
import UIComponents
import VPN

struct NetworkProtectionStatusView: View {

    static let defaultImageSize = CGSize(width: 32, height: 32)

    @Environment(\.colorScheme) var colorScheme

    @ObservedObject
    public var statusModel: NetworkProtectionStatusViewModel

    @ObservedObject
    public var feedbackFormModel: UnifiedFeedbackFormViewModel

    /// Drives the push to VPN settings when the Strict routing pill is tapped. A hidden `NavigationLink`
    /// attached to a list row (rather than the section header) performs the push, which is the reliable
    /// placement in a grouped `List`.
    @State private var isShowingVPNSettings = false

    var tipsModel: VPNTipsModel {
        statusModel.tipsModel
    }

    // MARK: - View

    var body: some View {
        List {
            if let errorItem = statusModel.error {
                NetworkProtectionErrorView(
                    title: errorItem.title,
                    message: errorItem.message
                )
            }

            toggle()

            locationDetails()

            if statusModel.isNetPEnabled && statusModel.hasServerInfo && !statusModel.isSnoozing {
                connectionDetails()
            }

            settings()
            about()
        }
        .padding(.top, statusModel.error == nil ? 0 : -20)
        .if(statusModel.animationsOn, transform: {
            $0
                .animation(.easeOut, value: statusModel.hasServerInfo)
                .animation(.easeOut, value: statusModel.shouldShowError)
        })
        .applyInsetGroupedListStyle()
        .sheet(isPresented: $statusModel.showAddWidgetEducationView) {
            if #available(iOS 17.0, *) {
                widgetEducationSheet()
            }
        }
        .onAppear {
            if #available(iOS 18.0, *) {
                tipsModel.handleStatusViewAppear()
            }
        }
        .onDisappear {
            if #available(iOS 18.0, *) {
                tipsModel.handleStatusViewDisappear()
            }
        }
    }

    @ViewBuilder
    private func toggle() -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.netPStatusViewTitle)
                        .daxBodyRegular()
                        .foregroundColor(.init(designSystemColor: .textPrimary))

                    HStack {
                        statusBadge(isConnected: statusModel.isNetPEnabled)

                        Text(statusModel.statusMessage)
                            .daxFootnoteRegular()
                            .foregroundColor(.init(designSystemColor: .textSecondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: Binding(
                    get: { statusModel.isNetPEnabled },
                    set: { isOn in
                        Task {
                            await statusModel.didToggleNetP(to: isOn)
                        }
                    }
                ))
                .disabled(statusModel.shouldDisableToggle)
                .toggleStyle(SwitchToggleStyle(tint: .init(designSystemColor: .accentPrimary)))
            }
            .padding([.top, .bottom], 2)
            .background(
                NavigationLink(destination: NetworkProtectionVPNSettingsView(scrollsToStrictRouting: true), isActive: $isShowingVPNSettings) {
                    EmptyView()
                }
                .opacity(0)
            )

            snooze()

        } header: {
            header()
        }
        .increaseHeaderProminence()
        .listRowBackground(Color(designSystemColor: .surface))

        Section {
            if #available(iOS 18.0, *) {
                widgetTipView()
                    .tipImageSize(Self.defaultImageSize)
                    .padding(.horizontal, 3)
            }

            if #available(iOS 18.0, *) {
                snoozeTipView()
                    .tipImageSize(Self.defaultImageSize)
                    .padding(.horizontal, 3)
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private func statusBadge(isConnected: Bool) -> some View {
        Circle()
            .foregroundStyle(isConnected ? Color(designSystemColor: .alertGreen) : Color(designSystemColor: .alertYellow))
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private func header() -> some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .center, spacing: 8) {
                if AppRebrand.isAppRebranded() {
                    headerAnimationView("vpn-animation", contentSize: CGSize(width: 128, height: 96))
                        .frame(width: 128, height: 96)
                } else if colorScheme == .light {
                    headerAnimationView("vpn-light-mode-legacy")
                } else {
                    headerAnimationView("vpn-dark-mode-legacy")
                }
                Text(statusModel.headerTitle)
                    .daxTitle2()
                    .multilineTextAlignment(.center)
                    .foregroundColor(.init(designSystemColor: .textPrimary))

                if statusModel.showStrictRoutingPill {
                    strictRoutingPill()
                }

                Text(statusModel.headerMessage)
                    .daxFootnoteRegular()
                    .multilineTextAlignment(.center)
                    .foregroundColor(.init(designSystemColor: .textSecondary))
                    .padding(.bottom, 8)
            }
            .padding(.bottom, 4)
            // Pads beyond the default header inset
            .padding(.horizontal, -16)
            .background(Color(designSystemColor: .background))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func snooze() -> some View {
        if statusModel.isSnoozing {
            Button(UserText.netPStatusViewWakeUp) {
                Task {
                    await statusModel.cancelSnooze()
                }
            }
            .tint(Color(designSystemColor: .accentPrimary))
            .disabled(statusModel.snoozeRequestPending)
        } else if statusModel.hasServerInfo {
            Button(UserText.netPStatusViewSnooze) {
                Task {
                    await statusModel.startSnooze()
                }
            }
            .tint(Color(designSystemColor: .accentPrimary))
            .disabled(statusModel.snoozeRequestPending)
        }
    }

    @ViewBuilder
    private func locationDetails() -> some View {
        Section {
            if !statusModel.isSnoozing, let location = statusModel.location {
                var locationAttributedString: AttributedString {
                    var attributedString = AttributedString(
                        statusModel.preferredLocation.isNearest ? "\(location) \(UserText.netPVPNLocationNearest)" : location
                    )
                    attributedString.foregroundColor = .init(designSystemColor: .textPrimary)
                    if let range = attributedString.range(of: UserText.netPVPNLocationNearest) {
                        attributedString[range].foregroundColor = Color(.init(designSystemColor: .textSecondary))
                    }
                    return attributedString
                }

                NavigationLink(destination: locationView()) {
                    NetworkProtectionLocationItemView(title: locationAttributedString, image: nil)
                }
            } else {
                var nearestLocationAttributedString: AttributedString {
                    var attributedString = AttributedString(statusModel.preferredLocation.title)
                    attributedString.foregroundColor = .init(designSystemColor: .textPrimary)
                    return attributedString
                }

                NavigationLink(destination: locationView()) {
                    NetworkProtectionLocationItemView(title: nearestLocationAttributedString, image: Image(uiImage: DesignSystemImages.Glyphs.Size24.location))
                }
            }
        } header: {
            Text(statusModel.isNetPEnabled ? UserText.vpnLocationConnected : UserText.vpnLocationSelected)
                .foregroundColor(.init(designSystemColor: .textSecondary))
        }
        .listRowBackground(Color(designSystemColor: .surface))

        Section {
            if #available(iOS 18.0, *) {
                geoswitchingTipView()
                    .tipImageSize(Self.defaultImageSize)
                    .padding(.horizontal, 3)
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private func locationView() -> some View {
        NetworkProtectionVPNLocationView()
            .onAppear {
                statusModel.handleUserOpenedVPNLocations()
            }
    }

    /// A compact status pill shown under the header while the VPN is on. It reflects the current Strict
    /// routing state — green when on, amber when off — and pushes the VPN settings when tapped.
    @ViewBuilder
    private func strictRoutingPill() -> some View {
        Button {
            isShowingVPNSettings = true
        } label: {
            HStack(spacing: 6) {
                Image(uiImage: DesignSystemImages.Glyphs.Size12.lockSolid)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 12, height: 12)

                Text(statusModel.enforceRoutes
                     ? UserText.netPStrictRoutingPillOn
                     : UserText.netPStrictRoutingPillOff)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .buttonStyle(StrictRoutingPillButtonStyle(isStrictRoutingOn: statusModel.enforceRoutes))
        .help(statusModel.enforceRoutes
              ? UserText.netPStrictRoutingPillTooltipOn
              : UserText.netPStrictRoutingPillTooltipOff)
    }

    @ViewBuilder
    private func connectionDetails() -> some View {
        Section {
            if let ipAddress = statusModel.ipAddress {
                NetworkProtectionConnectionDetailView(title: UserText.netPStatusViewIPAddress, value: ipAddress)
            }

            if statusModel.dnsSettings.usesCustomDNS {
                NetworkProtectionConnectionDetailView(title: UserText.netPStatusViewCustomDNS, value: String(describing: statusModel.dnsSettings))
            }

            NetworkProtectionThroughputItemView(
                title: UserText.vpnDataVolume,
                downloadSpeed: statusModel.downloadTotal ?? NetworkProtectionStatusViewModel.Constants.defaultDownloadVolume,
                uploadSpeed: statusModel.uploadTotal ?? NetworkProtectionStatusViewModel.Constants.defaultUploadVolume
            )
        } header: {
            Text(UserText.netPStatusViewConnectionDetails).foregroundColor(.init(designSystemColor: .textSecondary))
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private func settings() -> some View {
        Section {
            NavigationLink(destination: NetworkProtectionVPNSettingsView()) {
                HStack {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.settings)
                    Text(UserText.netPVPNSettingsTitle)
                }
                .daxBodyRegular()
                .foregroundColor(.init(designSystemColor: .textPrimary))
            }
        } header: {
            Text(UserText.netPStatusViewSettingsSectionTitle).foregroundColor(.init(designSystemColor: .textSecondary))
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private func about() -> some View {
        Section {
            NavigationLink(destination: LazyView(NetworkProtectionFAQView())) {
                HStack {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.help)
                    Text(UserText.netPVPNSettingsFAQ)
                }
                .daxBodyRegular()
                .foregroundColor(.init(designSystemColor: .textPrimary))
            }

            if statusModel.enablesUnifiedFeedbackForm {
                NavigationLink(destination: LazyView(UnifiedFeedbackRootView(viewModel: feedbackFormModel))) {
                    HStack {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.support)
                        Text(UserText.subscriptionFeedback)
                    }
                    .daxBodyRegular()
                    .foregroundColor(.init(designSystemColor: .textPrimary))
                }
            }
        } header: {
            Text(UserText.vpnAbout).foregroundColor(.init(designSystemColor: .textSecondary))
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    @ViewBuilder
    private func headerAnimationView(_ animationName: String, contentSize: CGSize? = nil) -> some View {
        let loopMode: LottieView.LoopMode = AppRebrand.isAppRebranded() ?
            .withIntro(
                .init(
                    // Skip the intro if NetP is enabled, but the user didn't manually trigger it
                    skipIntro: statusModel.isNetPEnabled && !statusModel.shouldDisableToggle,
                    introStartFrame: 0,
                    introEndFrame: 30,
                    loopStartFrame: 31,
                    loopEndFrame: 121
                )
            ) :
            .withIntro(
                .init(
                    skipIntro: statusModel.isNetPEnabled && !statusModel.shouldDisableToggle,
                    introStartFrame: 0,
                    introEndFrame: 100,
                    loopStartFrame: 130,
                    loopEndFrame: 370
                )
            )

        LottieView(
            lottieFile: animationName,
            loopMode: loopMode,
            isAnimating: $statusModel.isNetPEnabled,
            configure: Self.strictRoutingTint(spec: AppRebrand.isAppRebranded() ? .rebranded : .legacy,
                                              enforceRoutes: statusModel.enforceRoutes,
                                              colorScheme: colorScheme),
            contentSize: contentSize
        )
    }

    /// The Lottie keypaths the strict-routing tint recolors, per header animation variant.
    ///
    /// The legacy animation's groups and fills are unnamed in the JSON; lottie-ios decodes a
    /// null `nm` as "Layer", which is why the legacy keypaths read `<layer>.Layer.Layer.Color`.
    struct TintSpec {
        /// The badge circle behind the lock. Its color is keyframed to reveal below `revealFrame`.
        let badgeKeypath: String
        /// The frame at which the badge reveal completes: black before, accent after.
        let revealFrame: CGFloat
        /// Decorative arc lines that take the accent color (rebrand only).
        let accentLineKeypaths: [(fill: String, stroke: String)]
        /// The lock glyph, which takes the foreground color.
        let lockKeypaths: [String]

        static let rebranded = TintSpec(
            badgeKeypath: "badge-fill.badge-fill.Fill 1.Color",
            revealFrame: 14,
            accentLineKeypaths: ["Line", "Line 2", "Line 3"].map {
                (fill: "\($0).Shape 1.Fill 1.Color", stroke: "\($0).Shape 1.Stroke 1.Color")
            },
            lockKeypaths: ["lock 1.lock.Stroke 1.Color", "lock-body.lock-body.Fill 1.Color"]
        )

        static let legacy = TintSpec(
            badgeKeypath: "bg.Layer.Layer.Color",
            revealFrame: 35,
            accentLineKeypaths: [],
            lockKeypaths: ["lock-hook.Layer.Layer.Color", "lock-base.Layer.Layer.Color"]
        )
    }

    /// Tints the VPN header animation to reflect strict routing, sharing the pill's exact background
    /// colour so the lock circle and pill can't drift apart: the badge + arc lines use the pill's
    /// background (green when routing is enforced, yellow when not) and the lock takes the colour Figma
    /// shows on that badge — the green foreground when enforced, white when not.
    private static func strictRoutingTint(spec: TintSpec, enforceRoutes: Bool, colorScheme: ColorScheme) -> (LottieAnimationView) -> Void {
        { animationView in
            // Resolve against the SwiftUI colour scheme rather than the view's trait collection: the
            // latter can lag a live light/dark switch, leaving the tint on the previous mode's colours.
            let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
            let black = LottieColor(r: 0, g: 0, b: 0, a: 1)
            let white = LottieColor(r: 1, g: 1, b: 1, a: 1)
            let token: DesignSystemColor = enforceRoutes ? .vpnGreen : .vpnYellow
            let accent = UIColor(designSystemColor: token)
                .resolvedColor(with: traits)
                .lottieColorValue
            // Lock colour once the badge has lit up: it matches the pill's foreground for the state —
            // the green foreground when strict routing is on, the amber foreground when off. Before the
            // reveal the badge is black (also the disconnected state), so the lock is white to read on it.
            let revealedLock = enforceRoutes
                ? UIColor(designSystemColor: .vpnGreenForeground)
                    .resolvedColor(with: traits)
                    .lottieColorValue
                : UIColor(designSystemColor: .vpnYellowForeground)
                    .resolvedColor(with: traits)
                    .lottieColorValue

            // Circle: its color is keyframed to a light-up reveal, so a block preserves the
            // black off-state and swaps the accent in above the reveal.
            animationView.setValueProvider(
                ColorValueProvider(block: { frame in frame < spec.revealFrame ? black : accent }),
                keypath: AnimationKeypath(keypath: spec.badgeKeypath)
            )

            // Arc lines: static accent fill + stroke.
            for line in spec.accentLineKeypaths {
                animationView.setValueProvider(ColorValueProvider(accent),
                                               keypath: AnimationKeypath(keypath: line.fill))
                animationView.setValueProvider(ColorValueProvider(accent),
                                               keypath: AnimationKeypath(keypath: line.stroke))
            }

            // Lock: white while the badge is still black (pre-reveal / disconnected), then the
            // revealed colour — kept in step with the badge so it's always legible.
            for lock in spec.lockKeypaths {
                animationView.setValueProvider(
                    ColorValueProvider(block: { frame in frame < spec.revealFrame ? white : revealedLock }),
                    keypath: AnimationKeypath(keypath: lock))
            }
        }
    }

    // MARK: - Tips

    @available(iOS 18.0, *)
    @ViewBuilder
    private func geoswitchingTipView() -> some View {
        TipView(tipsModel.geoswitchingTip)
            .removeGroupedListStyleInsets()
            .tipCornerRadius(0)
            .tipBackground(Color(designSystemColor: .surface))
            .onAppear {
                tipsModel.handleGeoswitchingTipShown()
            }
            .task {
                var previousStatus = tipsModel.geoswitchingTip.status

                for await status in tipsModel.geoswitchingTip.statusUpdates {
                    if case .invalidated(let reason) = status {
                        if case .available = previousStatus {
                            tipsModel.handleGeoswitchingTipInvalidated(reason)
                        }
                    }

                    previousStatus = status
                }
            }
    }

    @available(iOS 18.0, *)
    @ViewBuilder
    private func snoozeTipView() -> some View {
        if statusModel.hasServerInfo {

            TipView(tipsModel.snoozeTip, action: statusModel.snoozeActionHandler(action:))
                .removeGroupedListStyleInsets()
                .tipCornerRadius(0)
                .tipBackground(Color(designSystemColor: .surface))
                .tint(Color.init(designSystemColor: .accentPrimary))
                .onAppear {
                    tipsModel.handleSnoozeTipShown()
                }
                .task {
                    var previousStatus = tipsModel.snoozeTip.status

                    for await status in tipsModel.snoozeTip.statusUpdates {
                        if case .invalidated(let reason) = status {
                            if case .available = previousStatus {
                                tipsModel.handleSnoozeTipInvalidated(reason)
                            }
                        }

                        previousStatus = status
                    }
                }
        }
    }

    @available(iOS 18.0, *)
    @ViewBuilder
    private func widgetTipView() -> some View {
        if !statusModel.isNetPEnabled && !statusModel.isSnoozing {

            TipView(tipsModel.widgetTip, action: statusModel.widgetActionHandler(action:))
                .removeGroupedListStyleInsets()
                .tipCornerRadius(0)
                .tipBackground(Color(designSystemColor: .surface))
                .tint(Color.init(designSystemColor: .accentPrimary))
                .onAppear {
                    tipsModel.handleWidgetTipShown()
                }
                .task {
                    var previousStatus = tipsModel.widgetTip.status

                    for await status in tipsModel.widgetTip.statusUpdates {
                        if case .invalidated(let reason) = status {
                            if case .available = previousStatus {
                                tipsModel.handleWidgetTipInvalidated(reason)
                            }
                        }

                        previousStatus = status
                    }
                }
        }
    }

    // MARK: - Sheets

    @available(iOS 17.0, *)
    private func widgetEducationSheet() -> some View {
        NavigationView {
            WidgetEducationView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(UserText.navigationTitleDone) {
                            statusModel.showAddWidgetEducationView = false
                        }
                    }
                }
        }
    }
}

private struct NetworkProtectionErrorView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.alertRecolorable)
                Text(title)
                    .daxBodyBold()
                    .foregroundColor(.primary)
            }
            if let attributedMessage = try? AttributedString(markdown: message) {
                Text(attributedMessage)
                    .daxBodyRegular()
                    .foregroundColor(.primary)
            } else {
                Text(message)
                    .daxBodyRegular()
                    .foregroundColor(.primary)
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }
}

private struct NetworkProtectionLocationItemView: View {
    let title: AttributedString
    let image: Image?

    var body: some View {
        HStack(spacing: 8) {
            if let image {
                image
            }

            Text(title)
                .daxBodyRegular()
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }
}

private struct NetworkProtectionConnectionDetailView: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .daxBodyRegular()
                .foregroundColor(.init(designSystemColor: .textPrimary))
            Spacer(minLength: 2)
            Text(value)
                .daxBodyRegular()
                .foregroundColor(.init(designSystemColor: .textSecondary))
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }
}

private struct NetworkProtectionThroughputItemView: View {
    let title: String
    let downloadSpeed: String
    let uploadSpeed: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .daxBodyRegular()
                .foregroundColor(.init(designSystemColor: .textPrimary))

            Spacer(minLength: 2)

            Image(.vpnDownload)
                .foregroundColor(.init(designSystemColor: .textSecondary))
            Text(downloadSpeed)
                .daxBodyRegular()
                .foregroundColor(.init(designSystemColor: .textSecondary))

            Image(.vpnUpload)
                .foregroundColor(.init(designSystemColor: .textSecondary))
                .padding(.leading, 4)
            Text(uploadSpeed)
                .daxBodyRegular()
                .foregroundColor(.init(designSystemColor: .textSecondary))
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }
}

extension NetworkProtectionDNSSettings {
    var usesCustomDNS: Bool {
        guard case .custom(let servers) = self, !servers.isEmpty else { return false }
        return true
    }
}

/// Renders the Strict routing pill as a coloured rounded rectangle. Pressing shows the state's darker
/// interaction variant (background + foreground) per the Figma spec.
private struct StrictRoutingPillButtonStyle: ButtonStyle {

    private static let cornerRadius: CGFloat = 44
    private static let height: CGFloat = 28

    let isStrictRoutingOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(textColor(isPressed: configuration.isPressed))
            .padding(padding)
            .frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: Self.cornerRadius).fill(fillColor(isPressed: configuration.isPressed)))
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    private func textColor(isPressed: Bool) -> Color {
        if isStrictRoutingOn {
            return Color(designSystemColor: isPressed ? .vpnGreenForegroundPressed : .vpnGreenForeground)
        }
        return Color(designSystemColor: isPressed ? .vpnYellowForegroundPressed : .vpnYellowForeground)
    }

    private func fillColor(isPressed: Bool) -> Color {
        if isStrictRoutingOn {
            return Color(designSystemColor: isPressed ? .vpnGreenPressed : .vpnGreen)
        }
        return Color(designSystemColor: isPressed ? .vpnYellowPressed : .vpnYellow)
    }

    private var padding: EdgeInsets {
        EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
    }
}
