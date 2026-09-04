//
//  SyncedDevicesListV2.swift
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

struct SyncedDevicesListV2: View {

    let devices: [SyncDevice]

    @State var hoveredDevice: SyncDevice?

    var presentDeviceDetails: ((SyncDevice) async -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if devices.isEmpty {
                ProgressView()
                    .padding()
            }

            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                if index > 0 {
                    SyncedDevicesSeparatorV2()
                }
                deviceRow(for: device)
            }
        }
    }

    @ViewBuilder
    private func deviceRow(for device: SyncDevice) -> some View {
        let row = deviceRowContent(for: device)

        if let presentDeviceDetails {
            row.accessibilityAction(named: Text(UserText.currentDeviceDetails)) {
                Task {
                    await presentDeviceDetails(device)
                }
            }
        } else {
            row
        }
    }

    private func deviceRowContent(for device: SyncDevice) -> some View {
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
            guard presentDeviceDetails != nil else { return }
            hoveredDevice = hovering ? device : nil
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func deviceAction(for device: SyncDevice) -> some View {
        if let presentDeviceDetails {
            Button(UserText.currentDeviceDetails) {
                Task {
                    await presentDeviceDetails(device)
                }
            }
            .accessibilityHidden(true)
            .visibility(hoveredDevice?.id == device.id ? .visible : .gone)
        }
    }
}

struct SyncedDevicesSeparatorV2: View {
    var body: some View {
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
            .padding(.leading, 8)
    }
}
