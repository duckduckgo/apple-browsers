//
//  PermissionAuthorizationSwiftUIView.swift
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

import SwiftUI
import Common

struct PermissionAuthorizationSwiftUIView: View {
    let domain: String
    let permissionType: PermissionType
    let onDeny: () -> Void
    let onAlwaysDeny: () -> Void
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void

    private var promptText: String {
        switch permissionType {
        case .geolocation:
            return String(format: UserText.locationPermissionAuthorizationFormat, domain)
        case .camera, .microphone:
            return String(format: UserText.devicePermissionAuthorizationFormat, domain, permissionType.localizedDescription.lowercased())
        case .popups:
            return String(format: UserText.popupWindowsPermissionAuthorizationFormat, domain, permissionType.localizedDescription.lowercased())
        case .externalScheme:
            if domain.isEmpty {
                return String(format: UserText.externalSchemePermissionAuthorizationNoDomainFormat, permissionType.localizedDescription)
            } else {
                return String(format: UserText.externalSchemePermissionAuthorizationFormat, domain, permissionType.localizedDescription)
            }
        }
    }

    private var denyButtonTitle: String {
        permissionType == .geolocation ? UserText.permissionPopupDenyButton : UserText.permissionPopupAlwaysDenyButton
    }

    private var allowButtonTitle: String {
        permissionType == .geolocation ? UserText.permissionPopupAllowButton : UserText.permissionPopupAlwaysAllowButton
    }

    private var denyAction: () -> Void {
        permissionType == .geolocation ? onDeny : onAlwaysDeny
    }

    private var allowAction: () -> Void {
        permissionType == .geolocation ? onAllow : onAlwaysAllow
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(promptText)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            HStack(spacing: 12) {
                Button(action: denyAction) {
                    Text(denyButtonTitle)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(designSystemColor: .controlsFillPrimary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.denyButton")

                Button(action: allowAction) {
                    Text(allowButtonTitle)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(designSystemColor: .controlsFillPrimary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.allowButton")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 400)
        .background(Color(designSystemColor: .containerFillPrimary))
    }
}

#if DEBUG
struct PermissionAuthorizationSwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            permissionType: .geolocation,
            onDeny: {},
            onAlwaysDeny: {},
            onAllow: {},
            onAlwaysAllow: {}
        )
        .previewDisplayName("Geolocation (Deny / Allow)")

        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            permissionType: .camera,
            onDeny: {},
            onAlwaysDeny: {},
            onAllow: {},
            onAlwaysAllow: {}
        )
        .previewDisplayName("Camera (Always Deny / Always Allow)")
    }
}
#endif
