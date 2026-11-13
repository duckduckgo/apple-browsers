//
//  SyncNotificationSettingsView.swift
//  DuckDuckGo
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

import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import SwiftUI

struct SyncNotificationPermissionCard: View {
    @ObservedObject var model: SyncNotificationSettingsViewModel

    var body: some View {
        if model.shouldShowPermissionCard {
            Section {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(UserText.syncNotificationsTitle)
                                .daxBodyBold()
                                .foregroundColor(Color(designSystemColor: .textPrimary))
                            Text(UserText.syncNotificationsDescription)
                                .daxBodyRegular()
                                .foregroundColor(Color(designSystemColor: .textSecondary))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Button(action: model.dismissPermissionCard) {
                            Image(uiImage: DesignSystemImages.Glyphs.Size16.close)
                        }
                        .buttonStyle(CloseButtonStyle())
                        .accessibilityLabel(UserText.syncNotificationsDismiss)
                        .accessibilityIdentifier("SyncNotificationPermissionCardDismiss")
                    }
                    Button {
                        Task { await model.enableNotifications() }
                    } label: {
                        Label(title: {
                            Text(UserText.syncNotificationsEnable)
                        }, icon: {
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.bell)
                        })
                    }
                    .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: true))
                    .disabled(model.isRequestingPermission)
                    .accessibilityIdentifier("SyncNotificationPermissionEnable")
                }
                .padding(24)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color(designSystemColor: .surfaceTertiary))
        }
    }
}

struct SyncNotificationSettingsRow: View {
    @ObservedObject var model: SyncNotificationSettingsViewModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.isToggleOn }, set: { enabled in
            Task { await model.setEnabled(enabled) }
        })) {
            Label(title: {
                Text(UserText.syncNotificationsTitle)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }, icon: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.bell)
                    .foregroundColor(Color(designSystemColor: .icons))
            })
        }
        .tint(Color(designSystemColor: .accentPrimary))
        .disabled(model.isRequestingPermission || model.authorizationStatus == nil)
        .accessibilityIdentifier("SyncNotificationsToggle")
    }
}

private struct SyncNotificationSettingsModifier: ViewModifier {
    @ObservedObject var model: SyncNotificationSettingsViewModel

    func body(content: Content) -> some View {
        content
            .task { await model.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await model.refresh() }
            }
            .alert(UserText.syncNotificationsSettingsTitle, isPresented: $model.isSettingsAlertPresented) {
                Button(UserText.syncNotificationsOpenSettings) {
                    Task { await model.openNotificationSettings() }
                }
                Button(UserText.cancelButton, role: .cancel) { }
            } message: {
                Text(UserText.syncNotificationsDescription)
            }
    }
}

extension View {
    @ViewBuilder
    func syncNotificationSettings(_ model: SyncNotificationSettingsViewModel?) -> some View {
        if let model {
            modifier(SyncNotificationSettingsModifier(model: model))
        } else {
            self
        }
    }
}
