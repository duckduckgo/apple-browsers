//
//  SyncedDevicesView.swift
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

import SwiftUI

struct SyncedDevicesView<ViewModel>: View where ViewModel: ManagementViewModel {

    @EnvironmentObject var model: ViewModel

    @State var isVisible = false

    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading) {
            SyncedDevicesList(devices: model.devices,
                              presentDeviceDetails: model.presentDeviceDetails,
                              presentRemoveDevice: model.presentRemoveDevice)
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
            Button(UserText.beginSyncButton) {
                Task {
                    await model.syncWithAnotherDevicePressed()
                }
            }
            .disabled(!model.isConnectingDevicesAvailable)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .roundedBorder()
    }
}

struct SyncedDeviceIcon: View {
    var kind: SyncDevice.Kind

    private var imageResource: ImageResource {
        switch kind {
        case .current, .desktop:
            return .syncedDeviceDesktop
        case .mobile:
            return .syncedDeviceMobile
        case .thirdParty:
            return .syncAllDevices
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
        Image(imageResource)
            .aspectRatio(contentMode: .fit)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct SyncedDevicesList: View {

    let devices: [SyncDevice]

    @State var hoveredDevice: SyncDevice?

    var presentDeviceDetails: ((SyncDevice) async -> Void)?
    var presentRemoveDevice: ((SyncDevice) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if devices.isEmpty {
                ProgressView()
                    .padding()
            }

            ForEach(devices) { device in
                if !device.isCurrent {
                    Rectangle()
                        .fill(Color(.blackWhite10))
                        .frame(height: 1)
                        .padding(.init(top: 0, leading: 10, bottom: 0, trailing: 10))
                }

                if device.isCurrent {
                    SyncPreferencesRow {
                        SyncedDeviceIcon(kind: device.kind)
                    } centerContent: {
                        HStack {
                            Text(device.name)
                            Text("(\(UserText.thisDevice))")
                                .foregroundColor(Color(NSColor.secondaryLabelColor))
                            Spacer()
                        }
                    } rightContent: {
                        if let presentDeviceDetails {
                            Button(UserText.currentDeviceDetails) {
                                Task {
                                    await presentDeviceDetails(device)
                                }
                            }
                        }
                    }
                } else {
                    SyncPreferencesRow {
                        SyncedDeviceIcon(kind: device.kind)
                    } centerContent: {
                        Text(device.name)
                    } rightContent: {
                        if let presentRemoveDevice = presentRemoveDevice {
                            Button(UserText.removeDeviceButton) {
                                presentRemoveDevice(device)
                            }
                            .visibility(hoveredDevice?.id == device.id ? .visible : .gone)
                        }
                    }.onHover { hovering in
                        hoveredDevice = hovering ? device : nil
                    }
                }
            }
            Rectangle()
                .fill(Color(.blackWhite10))
                .frame(height: 1)
                .padding(.init(top: 0, leading: 10, bottom: 0, trailing: 10))
        }
    }

}
