//
//  VPNStatusView.swift
//  DuckDuckGo
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


import Foundation
import AppIntents
import Core
import DesignResourcesKit
import SwiftUI
import WidgetKit
import NetworkExtension
import VPN

@available(iOSApplicationExtension 17.0, *)
struct VPNStatusView: View {

    @Environment(\.widgetFamily) var family: WidgetFamily
    @Environment(\.widgetRenderingMode) var widgetRenderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var entry: VPNStatusTimelineProvider.Entry

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private let snoozeTimingStore = NetworkProtectionSnoozeTimingStore(userDefaults: .networkProtectionGroupDefaults)

    @ViewBuilder
    var body: some View {
        DesignSystemWidgetContainerView {
            HStack {
                switch entry.status {
                case .status(let status):
                    connectionView(with: status)
                case .error, .notConfigured:
                    connectionView(with: .disconnected)
                }

                Spacer()
            }
        }
    }

    private func connectionView(with status: NEVPNStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            ResizableTintableImage(fullColor: UIImage(resource: headerImage(with: status)),
                          tintable: UIImage(resource: headerImage(with: status, tinted: true)))
                .padding(.bottom, 6)
                .accessibilityHidden(true)
                .frame(width: 55, height: 48)

            Text(title(with: status))
                .daxSubheadSemibold()
                .foregroundStyle(Color(designSystemColor: .textPrimary))
                .makeAccentable()

            Group {
                if status == .connected {
                    Text(snoozeTimingStore.isSnoozing ? UserText.vpnWidgetSnoozingUntil(endDate: snoozeEndDateString) : entry.location)
                } else {
                    Text(UserText.vpnWidgetDisconnectedSubtitle)
                }
            }
            .daxCaption()
            .foregroundStyle(Color(designSystemColor: .textPrimary))
            .opacity(status.isConnected ? 0.8 : 0.6)
            .makeAccentable()

            //  Should be padding of 7 here but use max space to ensure button's bottom padding looks right.
            Spacer()

            Group {
                switch status {
                case .connected:
                    let buttonTitle = snoozeTimingStore.isSnoozing ? UserText.vpnWidgetLiveActivityWakeUpButton : UserText.vpnWidgetDisconnectButton
                    let intent: any AppIntent = snoozeTimingStore.isSnoozing ? CancelSnoozeVPNIntent() : WidgetDisableVPNIntent()

                    Button(buttonTitle, intent: intent)
                        .makeAccentable(status == .connected)
                        .foregroundStyle(snoozeTimingStore.isSnoozing ?
                                         connectButtonForegroundColor(isDisabled: false) :
                                            disconnectButtonForegroundColor(isDisabled: status != .connected))
                        .tint(snoozeTimingStore.isSnoozing ?
                              Color(designSystemColor: .accent) :
                                disconnectButtonBackgroundColor(isDisabled: status != .connected)
                        )
                        .disabled(status != .connected)
                case .connecting, .reasserting:
                    Button(UserText.vpnWidgetDisconnectButton, intent: WidgetDisableVPNIntent())
                        .makeAccentable(status == .connected)
                        .foregroundStyle(disconnectButtonForegroundColor(isDisabled: status != .connected))
                        .tint(disconnectButtonBackgroundColor(isDisabled: status != .connected))
                        .disabled(status != .connected)
                case .disconnected, .disconnecting:
                    connectButton
                        .makeAccentable(status == .disconnected)
                        .foregroundStyle(connectButtonForegroundColor(isDisabled: status != .disconnected))
                        .tint(Color(designSystemColor: .accent))
                        .disabled(status != .disconnected)
                default:
                    EmptyView()
                }
            }
            .daxButton()
            .frame(height: 30)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .borderedStyle(widgetRenderingMode == .fullColor)
        }
    }

    private var snoozeEndDateString: String {
        if let activeTiming = snoozeTimingStore.activeTiming {
            return dateFormatter.string(from: activeTiming.endDate)
        } else {
            return ""
        }
    }

    private var connectButton: Button<Text> {
        switch entry.status {
        case .status:
            Button(UserText.vpnWidgetConnectButton, intent: WidgetEnableVPNIntent())
        case .error, .notConfigured:
            Button(UserText.vpnWidgetConnectButton) {
                openURL(DeepLinks.openVPN)
            }
        }
    }

    private func connectButtonForegroundColor(isDisabled: Bool) -> Color {
        let isDark = colorScheme == .dark
        let standardForegroundColor = isDark ? Color.black.opacity(0.84) : Color.white
        let disabledForegroundColor = isDark ? Color.white.opacity(0.36) : Color.black.opacity(0.36)
        return isDisabled ? disabledForegroundColor : standardForegroundColor
    }

    private func disconnectButtonBackgroundColor(isDisabled: Bool) -> Color {
        let isDark = colorScheme == .dark
        let standardBackgroundColor = isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.06)
        let disabledBackgroundColor = isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
        return isDisabled ? disabledBackgroundColor : standardBackgroundColor
    }

    private func disconnectButtonForegroundColor(isDisabled: Bool) -> Color {
        let isDark = colorScheme == .dark
        let defaultForegroundColor = isDark ? Color.white.opacity(0.84) : Color.black.opacity(0.84)
        let disabledForegroundColor = isDark ? Color.white.opacity(0.36) : Color.black.opacity(0.36)
        return isDisabled ? disabledForegroundColor : defaultForegroundColor
    }

    private func headerImage(with status: NEVPNStatus, tinted: Bool = false) -> ImageResource {
        switch status {
        case .connected:
            if snoozeTimingStore.isSnoozing {
                return tinted ? .vpnOffTinted : .vpnOff
            } else {
                return tinted ? .vpnOnTinted : .vpnOn
            }
        case .connecting, .reasserting: return tinted ? .vpnOnTinted : .vpnOn
        case .disconnecting, .disconnected: return tinted ? .vpnOffTinted : .vpnOff
        case .invalid: return tinted ? .vpnOffTinted : .vpnOff
        @unknown default: return tinted ? .vpnOffTinted : .vpnOff
        }
    }

    private func title(with status: NEVPNStatus) -> String {
        switch status {
        case .connected:
            let snoozeTimingStore = NetworkProtectionSnoozeTimingStore(userDefaults: .networkProtectionGroupDefaults)
            if snoozeTimingStore.activeTiming != nil {
                return UserText.vpnWidgetSnoozingStatus
            } else {
                return UserText.vpnWidgetConnectedStatus
            }
        case .connecting, .reasserting: return UserText.vpnWidgetConnectedStatus
        case .disconnecting, .disconnected, .invalid: return UserText.vpnWidgetDisconnectedStatus
        @unknown default: return "Unknown"
        }
    }

}
