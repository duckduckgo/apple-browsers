//
//  SyncSettingsView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import SwiftUI

public struct SyncSettingsView: View {

    @ObservedObject public var model: SyncSettingsViewModel

    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    @State var isSyncWithSetUpSheetVisible = false
    @State var isRecoverSyncedDataSheetVisible = false
    @State var isEnvironmentSwitcherInstructionsVisible = false
    @State var isDeviceAuthenticationSetupAlertVisible = false

    public init(model: SyncSettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        if model.isSyncingDevices {
            SwiftUI.ProgressView()
                .onReceive(timer) { _ in
                    if selectedDevice == nil {
                        model.delegate?.refreshDevices(clearDevices: false)
                    }
                }
        } else {
            List {
                if model.isSyncEnabled {

                    syncUnavailableViewWhileLoggedIn()
                        .listRowBackground(Color(designSystemColor: .surface))

                    turnOffSync()
                        .listRowBackground(Color(designSystemColor: .surface))

                    // Sync Paused Errors
                    if $model.isSyncPaused.wrappedValue {
                        syncPaused()
                            .listRowBackground(Color(designSystemColor: .surface))
                    }
                    if $model.isSyncBookmarksPaused.wrappedValue {
                        syncPaused(for: .bookmarks)
                            .listRowBackground(Color(designSystemColor: .surface))
                    }
                    if $model.isSyncCredentialsPaused.wrappedValue {
                        syncPaused(for: .credentials)
                            .listRowBackground(Color(designSystemColor: .surface))
                    }

                    if !model.invalidBookmarksTitles.isEmpty {
                        syncHasInvalidItems(for: .bookmarks)
                            .listRowBackground(Color(designSystemColor: .surface))
                    }

                    if !model.invalidCredentialsTitles.isEmpty {
                        syncHasInvalidItems(for: .credentials)
                            .listRowBackground(Color(designSystemColor: .surface))
                    }

                    devices()
                        .listRowBackground(Color(designSystemColor: .surface))

                    otherPlatformsLinks(source: .activated)
                        .listRowBackground(Color(designSystemColor: .surface))

                    options()
                        .listRowBackground(Color(designSystemColor: .surface))

                    saveRecoveryPDF()
                        .listRowBackground(Color(designSystemColor: .surface))

                    deleteAllData()
                        .listRowBackground(Color(designSystemColor: .surface))

                } else {

                    syncUnavailableViewWhileLoggedOut()
                        .listRowBackground(Color(designSystemColor: .surface))

                    syncWithAnotherDeviceView()
                        .listRowBackground(Color(designSystemColor: .surface))

                    otherOptions()
                        .listRowBackground(Color(designSystemColor: .surface))

                    otherPlatformsLinks(source: .notActivated)
                        .listRowBackground(Color(designSystemColor: .surface))
                }
            }
            .navigationTitle(UserText.syncTitle)
            .applyListStyle()
            .environmentObject(model)
            .alert(isPresented: $model.shouldShowPasscodeRequiredAlert) {
                Alert(
                    title: Text("Secure Your Device to Use Sync & Backup"),
                    message: Text("A device password is required to use Sync & Backup."),
                    dismissButton: .default(Text("Go to Settings"), action: {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        model.shouldShowPasscodeRequiredAlert = false
                    })
                )
            }
            .sheet(item: $selectedDevice) { device in
                Group {
                    if device.isThisDevice {
                        EditDeviceView(model: model.createEditDeviceModel(device))
                    } else {
                        RemoveDeviceView(model: model.createRemoveDeviceModel(device))
                    }
                }
                .modifier {
                    if #available(iOS 16.0, *) {
                        $0.presentationDetents([.medium])
                    } else {
                        $0
                    }
                }
            }
        }

    }

    // At some point work out how to change at least the fallback image to a resource.
    @ViewBuilder
    func deviceTypeImage(_ device: SyncSettingsViewModel.Device) -> some View {
        switch device.type {
        case "desktop":
            Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceDesktop)

        case "tablet":
            Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceTablet)

        default: // including phone
            Image(uiImage: DesignSystemImages.Glyphs.Size24.deviceMobile)
        }

    }

    @State var selectedDevice: SyncSettingsViewModel.Device?
}
