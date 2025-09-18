//
//  VPNWidget.swift
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

import Foundation
import AppIntents
import Core
import DesignResourcesKit
import SwiftUI
import WidgetKit
import NetworkExtension
import VPN

enum VPNStatus {
    case status(NEVPNStatus)
    case error
    case notConfigured

    var isConnecting: Bool {
        switch self {
        case .status(let status):
            return status == .connecting
        default:
            return false
        }
    }

    var isDisconnecting: Bool {
        switch self {
        case .status(let status):
            return status == .disconnecting
        default:
            return false
        }
    }

    var isConnected: Bool {
        switch self {
        case .status(let status):
            return status.isConnected
        default:
            return false
        }
    }
}

struct VPNStatusTimelineEntry: TimelineEntry {
    let date: Date
    let status: VPNStatus
    let location: String

    internal init(date: Date, status: VPNStatus = .notConfigured, location: String) {
        self.date = date
        self.status = status
        self.location = location
    }
}

class VPNStatusTimelineProvider: TimelineProvider {

    typealias Entry = VPNStatusTimelineEntry

    func placeholder(in context: Context) -> VPNStatusTimelineEntry {
        return VPNStatusTimelineEntry(date: Date(), status: .status(.connected), location: "Los Angeles")
    }

    func getSnapshot(in context: Context, completion: @escaping (VPNStatusTimelineEntry) -> Void) {
        let entry = VPNStatusTimelineEntry(date: Date(), status: .status(.connected), location: "Los Angeles")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VPNStatusTimelineEntry>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            let defaults = UserDefaults.networkProtectionGroupDefaults
            let location = defaults.string(forKey: NetworkProtectionUserDefaultKeys.lastSelectedServerCity) ?? "Unknown Location"
            let expiration = Date().addingTimeInterval(TimeInterval.minutes(5))

            if error != nil {
                let entry = VPNStatusTimelineEntry(date: expiration, status: .error, location: location)
                let timeline = Timeline(entries: [entry], policy: .atEnd)
                completion(timeline)
                return
            }

            guard let manager = managers?.first else {
                let entry = VPNStatusTimelineEntry(date: expiration, status: .notConfigured, location: location)
                let timeline = Timeline(entries: [entry], policy: .atEnd)
                completion(timeline)
                return
            }

            let status = manager.connection.status
            let entry = VPNStatusTimelineEntry(date: expiration, status: .status(status), location: location)
            let timeline = Timeline(entries: [entry], policy: .atEnd)

            completion(timeline)
        }
    }
}

extension NEVPNStatus {
    var description: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .disconnecting: return "Disconnecting"
        case .invalid: return "Invalid"
        case .reasserting: return "Reasserting"
        default: return "Unknown Status"
        }
    }

    var isConnected: Bool {
        switch self {
        case .connected, .connecting, .reasserting: return true
        case .disconnecting, .disconnected: return false
        default: return false
        }
    }
}

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
        Group {
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
        .padding(16)
        .containerBackground(for: .widget) {
            Color(designSystemColor: .surfaceCanvas)
        }
    }

    private func connectionView(with status: NEVPNStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(headerImageName(with: status))
                .useFullColorRendering()
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            Text(title(with: status))
                .daxSubheadSemibold()
                .foregroundStyle(Color(designSystemColor: .textPrimary))

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

    private func headerImageName(with status: NEVPNStatus) -> String {
        switch status {
        case .connected:
            if snoozeTimingStore.isSnoozing {
                return "vpn-off"
            } else {
                return "vpn-on"
            }
        case .connecting, .reasserting: return "vpn-on"
        case .disconnecting, .disconnected: return "vpn-off"
        case .invalid: return "vpn-off"
        @unknown default: return "vpn-off"
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

@available(iOSApplicationExtension 17.0, *)
struct VPNStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.vpn.rawValue, provider: VPNStatusTimelineProvider()) { entry in
            VPNStatusView(entry: entry).widgetURL(DeepLinks.openVPN)
        }
        .configurationDisplayName(UserText.vpnWidgetGalleryDisplayName)
        .description(UserText.vpnWidgetGalleryDescription)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct VPNStatusView_Previews: PreviewProvider {

    static let connectedState = VPNStatusTimelineProvider.Entry(
        date: Date(),
        status: .status(.connected),
        location: "Paoli, PA"
    )

    static let disconnectedState = VPNStatusTimelineProvider.Entry(
        date: Date(),
        status: .status(.disconnected),
        location: "Paoli, PA"
    )

    static let notConfiguredState = VPNStatusTimelineProvider.Entry(
        date: Date(),
        status: .notConfigured,
        location: "Paoli, PA"
    )

    static var previews: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            VPNStatusView(entry: connectedState)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .light)

            VPNStatusView(entry: connectedState)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .dark)

            VPNStatusView(entry: disconnectedState)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .light)

            VPNStatusView(entry: disconnectedState)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .dark)

            VPNStatusView(entry: notConfiguredState)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .light)

            VPNStatusView(entry: notConfiguredState)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .dark)
        } else {
            Text("iOS 17 required")
        }
    }
}

extension View {

    @ViewBuilder
    func borderedStyle(_ isBordered: Bool) -> some View {
        if isBordered {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.automatic)
        }
    }

}
