//
//  VPNExclusionSuggestionAlert.swift
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
import SwiftUIExtensions

public struct VPNExclusionSuggestionAlert: ModalView {

    public enum UserAction: Sendable {
        case stopVPN
        case excludeApp
        case excludeWebsite
    }

    struct Spacing {
        static let viewEdgesToContent: CGFloat = 20
        static let viewContentItemsToEachOther: CGFloat = 16
    }

    struct Sizing {
        static let viewWidth: CGFloat = 500
    }

    @Environment(\.dismiss) private var dismiss
    @Binding private var userAction: UserAction
    @Binding private var dontAskAgain: Bool
    @State private var redraw: Bool = false

    public init(userAction: Binding<UserAction>, dontAskAgain: Binding<Bool>) {
        _userAction = userAction
        _dontAskAgain = dontAskAgain
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.viewContentItemsToEachOther) {

            VStack(alignment: .leading, spacing: Spacing.viewContentItemsToEachOther) {
                Text(UserText.vpnExclusionSuggestionAlertTitle)
                    .font(.system(size: 15))
                    .fontWeight(.semibold)

                Text(UserText.vpnExclusionSuggestionAlertDescription)
                    .multilineText()
                    .multilineTextAlignment(.leading)
                    .fixMultilineScrollableText()
                    .frame(alignment: .leading)

                Toggle(isOn: .init(get: {
                    dontAskAgain
                }, set: { newValue in
                    dontAskAgain = newValue
                    redraw.toggle()
                })) {
                    Text(UserText.vpnExclusionSuggestionAlertDontAskAgainTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: Spacing.viewEdgesToContent, leading: Spacing.viewEdgesToContent, bottom: 0, trailing: Spacing.viewEdgesToContent))

            Divider()

            HStack {
                Button(UserText.vpnExclusiveSuggestionAlertActionExcludeAWebsite) {
                    userAction = .excludeWebsite
                    dismiss()
                }
                .buttonStyle(DismissActionButtonStyle())

                Button(UserText.vpnExclusiveSuggestionAlertActionExcludeAnApp) {
                    userAction = .excludeApp
                    dismiss()
                }
                .buttonStyle(DismissActionButtonStyle())

                Spacer()

                Button(UserText.vpnExclusiveSuggestionAlertActionTurnOffVPN) {
                    userAction = .stopVPN
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(DefaultActionButtonStyle(enabled: true))
            }
            .padding(EdgeInsets(top: 0, leading: Spacing.viewEdgesToContent, bottom: Spacing.viewEdgesToContent, trailing: Spacing.viewEdgesToContent))
        }
        .frame(width: Sizing.viewWidth)
    }
}

struct VPNExclusionSuggestionAlert_Previews: PreviewProvider {

    static var previews: some View {
        VPNExclusionSuggestionAlert(userAction: .constant(.stopVPN), dontAskAgain: .constant(false))
    }
}
