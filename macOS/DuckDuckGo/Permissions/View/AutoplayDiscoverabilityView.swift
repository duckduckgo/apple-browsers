//
//  AutoplayDiscoverabilityView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

// MARK: - Autoplay Disclaimer / Discoverability View

struct AutoplayDiscoverabilityView: View {

    let onClickSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.infoRecolorable)

            VStack(alignment: .leading, spacing: 10) {
                Text(UserText.permissionCenterAutoplayDisclaimerTitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .accentAltTextSecondary))

                messageWithLink
                    .lineSpacing(5)
                    .cursor(.pointingHand)
                    .onTapGesture(perform: onClickSettings)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(designSystemColor: .accentAltGlowPrimary))
        )
    }
}

private extension AutoplayDiscoverabilityView {

    var messageWithLink: some View {
        Text(UserText.permissionCenterAutoplayDisclaimerMessage)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .accentAltTextSecondary))
        + Text(verbatim: " ")
        + Text(UserText.permissionCenterAutoplayDisclaimerSettingsLink)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .accentTextPrimary))
    }
}

#if DEBUG
#Preview {
    AutoplayDiscoverabilityView(onClickSettings: {})
        .padding(16)
        .frame(width: 400)
        .background(Color(designSystemColor: .permissionCenterBackground))
}
#endif
