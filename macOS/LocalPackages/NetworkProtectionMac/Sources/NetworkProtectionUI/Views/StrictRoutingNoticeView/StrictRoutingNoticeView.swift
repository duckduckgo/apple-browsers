//
//  StrictRoutingNoticeView.swift
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

/// A persistent notice shown in the VPN status view while the VPN is on but Strict routing is off,
/// prompting the user to turn it back on.
///
/// Unlike the TipKit tips elsewhere in the status view, this is a plain state-driven view: it has no
/// dismiss control and no recurrence rules. It appears whenever the condition holds and disappears as
/// soon as Strict routing is enabled.
struct StrictRoutingNoticeView: View {

    /// Invoked when the user taps the action button to turn Strict routing on.
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.networkProtectionStrictRoutingNoticeTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineText()

                    Text(UserText.networkProtectionStrictRoutingNoticeMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Button(action: onEnable) {
                Text(UserText.networkProtectionStrictRoutingNoticeActionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tipBackground)))
    }
}
