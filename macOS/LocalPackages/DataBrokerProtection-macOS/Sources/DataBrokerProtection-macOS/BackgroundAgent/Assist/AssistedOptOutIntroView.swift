//
//  AssistedOptOutIntroView.swift
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

import DataBrokerProtectionCore
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

/// Shown where the broker's page will be, until the user starts the request.
struct AssistedOptOutIntroView: View {
    @ObservedObject var session: AssistedOptOutSession

    private var brokerName: String { session.broker.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: DesignSystemImages.Color.Size96.duckDuckGo)
                .resizable()
                .frame(width: 48, height: 48)
            Text("Ready to remove you from \(brokerName)")
                .font(.system(size: 30))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
            Text("We\u{2019}ll open their opt-out form here and fill it in for you.")
                .font(.system(size: 16))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            whereWeNeedYourHelp
                .padding(.top, 22)
            HStack(spacing: 16) {
                Button {
                    session.begin()
                } label: {
                    Text("Start request")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .frame(height: 48)
                        .background(Capsule().fill(Color(designSystemColor: .accentPrimary)))
                }
                .buttonStyle(.plain)
                Text("About a minute \u{00B7} stop anytime")
                    .font(.system(size: 14))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var whereWeNeedYourHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHERE WE NEED YOUR HELP")
                .font(.system(size: 12, weight: .medium))
                .kerning(1.5)
                .foregroundColor(Color(designSystemColor: .textSecondary))
            helpCard(icon: DesignSystemImages.Glyphs.Size16.check,
                     title: "Prove you\u{2019}re human",
                     detail: "\(brokerName) may ask you to prove you\u{2019}re human. We\u{2019}ll pause and show you where.")
            helpCard(icon: DesignSystemImages.Glyphs.Size16.sendPlane,
                     title: "Review and submit",
                     detail: "We\u{2019}ll show you what we entered. Nothing is sent until you press Submit.")
        }
    }

    private func helpCard(icon: NSImage, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: icon)
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .statusWarningContentPrimary))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(designSystemColor: .statusWarningFillPrimary)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .assistedOptOutCallout()
    }
}

extension View {
    /// The yellow card the window uses wherever the user has to do something.
    func assistedOptOutCallout() -> some View {
        background(RoundedRectangle(cornerRadius: 14).fill(Color(designSystemColor: .statusWarningFillPrimary)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(designSystemColor: .statusYellowPrimary), lineWidth: 1.5))
    }
}
