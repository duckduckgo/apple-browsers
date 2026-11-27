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
import SwiftUI

struct SyncNotificationPermissionCard: View {
    @ObservedObject var model: SyncNotificationSettingsViewModel

    var body: some View {
        if #available(iOS 18.0, *), model.shouldShowPermissionCard {
            Section {
                SyncSettingsTipView(
                    tip: SyncSettingsTip(kind: .notificationPermission,
                                         titleText: UserText.syncNotificationsTitle,
                                         messageText: UserText.syncNotificationsDescription,
                                         actionText: UserText.syncNotificationsEnable),
                    action: { Task { await model.enableNotifications() } },
                    dismiss: model.dismissPermissionCard
                )
                .disabled(model.isRequestingPermission)
                .accessibilityIdentifier("SyncNotificationPermissionCard")
            }
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
                Text(UserText.syncNotificationsSettingLabel)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }, icon: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.bellNotification)
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
                Text(UserText.syncNotificationsSettingsMessage)
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
