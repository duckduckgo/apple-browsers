//
//  TunnelControllerView.swift
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

import SwiftUI
import AppKit
import SwiftUIExtensions
import Combine
import VPN
import Lottie
import os.log
import TipKit
import DesignResourcesKit

public struct TunnelControllerView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dismiss) private var dismiss

    // MARK: - Model

    /// The view model that this instance will use.
    ///
    @ObservedObject
    var model: TunnelControllerViewModel

    private let isAppRebranded = DesignSystemRebrand.isAppRebranded()

    // MARK: - Initializers

    public init(model: TunnelControllerViewModel) {
        self.model = model
    }

    @EnvironmentObject
    private var tipsModel: VPNTipsModel

    // MARK: - View Contents

    public var body: some View {
        Group {
            headerView()
                .disabled(on: !isEnabled)

            featureToggleRow()

            if #available(macOS 14.0, *),
               tipsModel.canShowAutoconnectTip {

                TipView(tipsModel.autoconnectTip, action: tipsModel.autoconnectTipActionHandler)
                    .tipImageSize(VPNTipsModel.imageSize)
                    .tipBackground(Color(.tipBackground))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .onAppear {
                        tipsModel.handleAutoconnectionTipShown()
                    }
                    .task {
                        var previousStatus = tipsModel.autoconnectTip.status

                        for await status in tipsModel.autoconnectTip.statusUpdates {
                            if case .invalidated(let reason) = status {
                                if case .available = previousStatus {
                                    tipsModel.handleAutoconnectTipInvalidated(reason)
                                }
                            }

                            previousStatus = status
                        }
                    }
            }

            if model.exclusionsFeatureEnabled {
                SiteTroubleshootingView()
                    .padding(.top, 5)

                if #available(macOS 14.0, *),
                   tipsModel.canShowDomainExclusionsTip {

                    TipView(tipsModel.domainExclusionsTip)
                        .tipImageSize(VPNTipsModel.imageSize)
                        .tipBackground(Color(.tipBackground))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .onAppear {
                            tipsModel.handleDomainExclusionsTipShown()
                        }
                        .task {
                            var previousStatus = tipsModel.domainExclusionsTip.status

                            for await status in tipsModel.domainExclusionsTip.statusUpdates {
                                if case .invalidated(let reason) = status {
                                    if case .available = previousStatus {
                                        tipsModel.handleDomainExclusionTipInvalidated(reason)
                                    }
                                }

                                previousStatus = status
                            }
                        }
                }
            }

            Divider()
                .padding(EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9))

            locationView()

            if model.showServerDetails {
                connectionStatusView()
                    .disabled(on: !isEnabled)
            }
        }
        .onAppear {
            if #available(macOS 14.0, *) {
                tipsModel.handleTunnelControllerAppear()
            }
        }
        .onDisappear {
            if #available(macOS 14.0, *) {
                tipsModel.handleTunnelControllerDisappear()
            }
        }
    }

    // MARK: - Composite Views

    /// Main image, feature ON/OFF and feature description
    ///
    private func headerView() -> some View {
        VStack(spacing: 0) {
            headerAnimationView()
                .frame(width: 100, height: 75)

            Text(model.featureStatusDescription)
                .applyTitleAttributes(colorScheme: colorScheme)
                .padding([.top], 8)
                .multilineText()

            if model.showStrictRoutingPill {
                StrictRoutingPillView(isStrictRoutingOn: model.enforceRoutes) {
                    model.showVPNSettings()
                    dismiss()
                }
                .padding(.top, 8)
            }

            Text(model.headerMessage)
                .multilineText()
                .multilineTextAlignment(.center)
                .applyDescriptionAttributes()
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
    }

    @ViewBuilder
    private func headerAnimationView() -> some View {
        if isAppRebranded {
            headerAnimationView("vpn-animation")
        } else if colorScheme == .light {
            headerAnimationView("vpn-light-mode")
        } else {
            headerAnimationView("vpn-dark-mode")
        }
    }

    @ViewBuilder
    private func headerAnimationView(_ animationName: String) -> some View {
        let tintedAnimationView = LottieView(animation: .named(animationName))
            .configure { [isAppRebranded, enforceRoutes = model.enforceRoutes, colorScheme] animationView in
                Self.applyStrictRoutingTint(spec: isAppRebranded ? .rebranded : .legacy,
                                            enforceRoutes: enforceRoutes,
                                            colorScheme: colorScheme,
                                            to: animationView)
            }

        // Re-create the view on a light/dark switch so the tint is re-applied for the new scheme;
        // otherwise it keeps the colours resolved when the view was first configured.
        if isAppRebranded {
            tintedAnimationView
                .playing(withIntro: .init(
                    skipIntro: model.isConnectedOrConnecting && !model.isToggleDisabled,
                    introStartFrame: 0,
                    introEndFrame: 30,
                    loopStartFrame: 30,
                    loopEndFrame: 120,
                ), isAnimating: model.isConnectedOrConnecting)
                .id(colorScheme)
        } else {
            tintedAnimationView
                .playing(withIntro: .init(
                    skipIntro: model.isConnectedOrConnecting && !model.isToggleDisabled,
                    introStartFrame: 0,
                    introEndFrame: 100,
                    loopStartFrame: 130,
                    loopEndFrame: 370
                ), isAnimating: model.isConnectedOrConnecting)
                .id(colorScheme)
        }
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
    /// background (green when enforced, yellow when not) and the lock takes the colour Figma shows on
    /// that badge — the green foreground when enforced, white when not.
    private static func applyStrictRoutingTint(spec: TintSpec, enforceRoutes: Bool, colorScheme: ColorScheme, to animationView: LottieAnimationView) {
        let black = LottieColor(r: 0, g: 0, b: 0, a: 1)
        let white = LottieColor(r: 1, g: 1, b: 1, a: 1)
        let accentToken: DesignSystemColor = enforceRoutes ? .vpnGreen : .vpnYellow
        let accent = Self.lottieColor(designSystemColor: accentToken, colorScheme: colorScheme)
        // Lock colour once the badge has lit up: it matches the pill's foreground for the state —
        // the green foreground when strict routing is on, the amber foreground when off. Before the
        // reveal the badge is black (also the disconnected state), so the lock is white to read on it.
        let revealedLock = enforceRoutes
            ? Self.lottieColor(designSystemColor: .vpnGreenForeground, colorScheme: colorScheme)
            : Self.lottieColor(designSystemColor: .vpnYellowForeground, colorScheme: colorScheme)

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

    /// Resolves a design-system color to a `LottieColor` for use in a value provider.
    /// (Lottie's `lottieColorValue` convenience is UIKit-only, so we bridge via `NSColor`.)
    /// Resolved against an appearance built from the SwiftUI colour scheme rather than the view's
    /// `effectiveAppearance`, which can lag a live light/dark switch and leave the tint on the old mode.
    private static func lottieColor(designSystemColor: DesignSystemColor, colorScheme: ColorScheme) -> LottieColor {
        var lottieColor = LottieColor(r: 0, g: 0, b: 0, a: 1)
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            if let color = NSColor(designSystemColor: designSystemColor).usingColorSpace(.sRGB) {
                lottieColor = LottieColor(r: Double(color.redComponent),
                                          g: Double(color.greenComponent),
                                          b: Double(color.blueComponent),
                                          a: Double(color.alphaComponent))
            }
        }
        return lottieColor
    }

    @ViewBuilder
    private func statusBadge(isConnected: Bool) -> some View {
        Circle()
            .fill(isConnected ? Color(designSystemColor: .alertGreen) : Color(designSystemColor: .alertYellow))
            .frame(width: 8, height: 8)
    }

    /// Connected/Selected location
    ///
    private func locationView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.isVPNEnabled ? UserText.vpnLocationConnected : UserText.vpnLocationSelected)
                .applySectionHeaderAttributes(colorScheme: colorScheme)
                .padding(EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9))

            MenuItemCustomButton {
                if #available(macOS 14.0, *) {
                    tipsModel.handleLocationsShown()
                }

                model.showLocationSettings()
                dismiss()
            } label: { isHovered in
                HStack(alignment: .center, spacing: 10) {
                    if let emoji = model.emoji {
                        Text(emoji)
                            .font(.system(size: 13))
                            .frame(width: 26, height: 26)
                            .background(Color(hex: "B2B2B2").opacity(0.3))
                            .clipShape(Circle())
                    } else if model.wantsNearestLocation {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "B2B2B2").opacity(0.3))
                                .frame(width: 26, height: 26)
                            if isHovered {
                                Image(NetworkProtectionAsset.nearestAvailable)
                                    .renderingMode(.template)
                                    .foregroundColor(.white)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(NetworkProtectionAsset.nearestAvailable)
                                    .renderingMode(colorScheme == .light ? .original : .template)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }

                    if isHovered {
                        Text(model.plainLocation)
                            .applyLocationAttributes()
                            .foregroundColor(.white)
                    } else {
                        Text(model.formattedLocation(colorScheme: colorScheme))
                            .applyLocationAttributes()
                    }
                }
            }

            if #available(macOS 14.0, *),
               tipsModel.canShowTips {

                TipView(tipsModel.geoswitchingTip)
                    .tipImageSize(VPNTipsModel.imageSize)
                    .tipBackground(Color(.tipBackground))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
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

            dividerRow()
        }
    }

    /// Connection status: server IP address and location
    ///
    private func connectionStatusView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.networkProtectionStatusViewConnDetails)
                .applySectionHeaderAttributes(colorScheme: colorScheme)
                .padding(EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9))

            connectionDetailRow(title: UserText.networkProtectionStatusViewIPAddress,
                                details: model.serverAddress)

            if model.dnsSettings.usesCustomDNS {
                connectionDetailRow(title: UserText.vpnDnsServer,
                                    details: String(describing: model.dnsSettings))
            }

            dataVolumeRow(title: UserText.vpnDataVolume, dataVolume: model.formattedDataVolume)

            dividerRow()
        }
    }

    // MARK: - Rows

    private func dividerRow() -> some View {
        Divider()
            .padding(EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9))
    }

    private func featureToggleRow() -> some View {
        Toggle(isOn: model.isToggleOn) {
            HStack {
                Text(UserText.networkProtectionStatusViewConnLabel)
                    .applyLabelAttributes(colorScheme: colorScheme)
                    .frame(alignment: .leading)
                    .fixedSize()
                    .disabled(on: !isEnabled)

                Spacer(minLength: 8)

                statusBadge(isConnected: model.isConnectedOrConnecting)

                Text(model.connectionStatusDescription)
                    .applyTimerAttributes(colorScheme: colorScheme)
                    .fixedSize()
                    .disabled(on: !isEnabled)

                Spacer()
                    .frame(width: 8)
            }
        }
        .disabled(!isEnabled || model.isToggleDisabled)
        .toggleStyle(.switch)
        .padding(EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9))
    }

    private func connectionDetailRow(title: String, details: String) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .applyLabelAttributes(colorScheme: colorScheme)
                .fixedSize()

            Spacer(minLength: 16)

            Text(details)
                .makeSelectable()
                .applyConnectionStatusDetailAttributes(colorScheme: colorScheme)
                .fixedSize()
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 0, trailing: 9))
    }

    private func dataVolumeRow(title: String, dataVolume: TunnelControllerViewModel.FormattedDataVolume) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .applyLabelAttributes(colorScheme: colorScheme)
                .fixedSize()

            Spacer(minLength: 2)

            Group {
                Image(NetworkProtectionAsset.dataReceived)
                    .renderingMode(colorScheme == .light ? .original : .template)
                    .frame(width: 12, height: 12)
                Text(dataVolume.dataReceived)
                    .applyDataVolumeAttributes(colorScheme: colorScheme)
                Image(NetworkProtectionAsset.dataSent)
                    .renderingMode(colorScheme == .light ? .original : .template)
                    .frame(width: 12, height: 12)
                    .padding(.leading, 4)
                Text(dataVolume.dataSent)
                    .applyDataVolumeAttributes(colorScheme: colorScheme)
            }
            .fixedSize()
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 9))
    }
}
