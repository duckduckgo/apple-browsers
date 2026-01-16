//
//  SystemDisabledNotificationInfoView.swift
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

import AppKit
import DesignResourcesKit
import PixelKit
import SwiftUI

/// Informational view shown when notification permission is blocked because system notifications are disabled.
/// Matches the layout of `systemDisabledPermissionView` in `PermissionAuthorizationSwiftUIView`.
struct SystemDisabledNotificationInfoView: View {
    let domain: String

    var body: some View {
        VStack(spacing: 20) {
            // Prompt: "Allow "domain" to send you notifications?"
            Text(String(format: UserText.notificationPermissionAuthorizationFormat, domain))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Warning + link (direct string references)
            (Text(UserText.permissionPopoverSystemNotificationDisabledStandalone)
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textSecondary))
            + Text(" ")
            + Text(UserText.permissionCenterSystemSettingsNotifications)
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textLink)))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .cursor(.pointingHand)
                .onTapGesture {
                    openSystemSettings()
                }
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(designSystemColor: .surfaceSecondary))
    }

    private func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        PixelKit.fire(PermissionPixel.systemPreferencesOpened(permissionType: .notification))
        NSWorkspace.shared.open(url)
    }
}
