//
//  SyncedDevicesViewV2.swift
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
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit
import DesignResourcesKitIcons

#if DEBUG
import PreviewSnapshots
#endif

struct SyncedDevicesViewV2<ViewModel>: View where ViewModel: ManagementViewModel {

    @EnvironmentObject var model: ViewModel

    @State var isVisible = false

    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SyncedDevicesListV2(devices: model.devices,
                                presentDeviceDetails: model.presentDeviceDetails)
            .onReceive(timer) { _ in
                guard isVisible else { return }
                model.refreshDevices()
            }
            .onAppear {
                isVisible = true
            }
            .onDisappear {
                isVisible = false
            }

            Button {
                Task {
                    await model.syncWithAnotherDevicePressed()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(nsImage: DesignSystemImages.Glyphs.Size24.qrScan)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(UserText.beginSyncButtonV2)
                }
            }
            .buttonStyle(SyncWithAnotherDeviceButtonStyleV2(enabled: model.isConnectingDevicesAvailable))
            .disabled(!model.isConnectingDevicesAvailable)
            .padding(8)
        }
        .syncRoundedBorder(cornerRadius: 12)
    }
}

private struct SyncedDevicesListV2: View {

    let devices: [SyncDevice]

    @State var hoveredDevice: SyncDevice?

    var presentDeviceDetails: ((SyncDevice) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if devices.isEmpty {
                ProgressView()
                    .padding()
            }

            ForEach(devices) { device in
                if !device.isCurrent {
                    separator
                }
                deviceRow(for: device)
            }
            separator
        }
    }

    @ViewBuilder
    private func deviceRow(for device: SyncDevice) -> some View {
        SyncPreferencesRow {
            SyncedDeviceIconV2(kind: device.kind)
        } centerContent: {
            HStack {
                Text(device.name)
                if device.isCurrent {
                    Text("(\(UserText.thisDevice))")
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                Spacer()
            }
        } rightContent: {
            deviceAction(for: device)
        }
        .onHover { hovering in
            hoveredDevice = hovering ? device : nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(UserText.currentDeviceDetails)) {
            presentDeviceDetails?(device)
        }
    }

    @ViewBuilder
    private func deviceAction(for device: SyncDevice) -> some View {
        if let presentDeviceDetails {
            Button(UserText.currentDeviceDetails) {
                presentDeviceDetails(device)
            }
            .accessibilityHidden(true)
            .visibility(hoveredDevice?.id == device.id ? .visible : .gone)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(.blackWhite10))
            .frame(height: 1)
            .padding(.init(top: 0, leading: 10, bottom: 0, trailing: 10))
    }
}

struct SyncedDeviceIconV2: View {
    var kind: SyncDevice.Kind

    private var image: DesignSystemImage {
        switch kind {
        case .current, .desktop:
            return DesignSystemImages.Glyphs.Size16.deviceLaptop
        case .mobile:
            return DesignSystemImages.Glyphs.Size16.deviceMobile
        case .thirdParty:
            return DesignSystemImages.Glyphs.Size16.deviceAll
        }
    }

    private var accessibilityIdentifier: String {
        switch kind {
        case .current, .desktop:
            return "SyncSettings.syncedDevice.desktop"
        case .mobile:
            return "SyncSettings.syncedDevice.mobile"
        case .thirdParty:
            return "SyncSettings.syncedDevice.thirdParty"
        }
    }

    var body: some View {
        Image(nsImage: image)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#if DEBUG
struct SyncedDevicesViewV2_Previews: PreviewProvider {
    typealias State = PreviewManagementViewModel

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Multiple devices", state: .enabled),
            .init(name: "Single device", state: .enabledSingleDevice),
            .init(name: "Loading devices", state: .enabledLoadingDevices)
        ],
        configure: { model in
            DesignSystemRebrand.isAppRebranded = { true }
            return SyncedDevicesViewV2<PreviewManagementViewModel>()
                .environmentObject(model)
                .frame(width: 512)
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
        }
    )
}
#endif
