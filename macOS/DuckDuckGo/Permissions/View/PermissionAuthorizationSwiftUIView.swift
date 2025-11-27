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
    let onNeverAllow: () -> Void
    let onAlwaysAllow: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Allow \"\(domain)\" to use your current location?")
                .font(.system(size: 15))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            HStack(spacing: 12) {
                Button(action: onNeverAllow) {
                    Text(UserText.permissionPopupNeverAllowButton)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(designSystemColor: .controlsFillSecondary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.neverAllowButton")

                Button(action: onAlwaysAllow) {
                    Text(UserText.permissionPopupAlwaysAllowButton)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(designSystemColor: .controlsFillSecondary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.alwaysAllowButton")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 400)
    }
}

#if DEBUG
struct PermissionAuthorizationSwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            onNeverAllow: {},
            onAlwaysAllow: {}
        )
        .previewDisplayName("Light Mode")

        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            onNeverAllow: {},
            onAlwaysAllow: {}
        )
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark Mode")
    }
}
#endif
