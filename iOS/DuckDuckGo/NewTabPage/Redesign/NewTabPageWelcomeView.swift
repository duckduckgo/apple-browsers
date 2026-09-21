//
//  NewTabPageWelcomeView.swift
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
import SwiftUI

struct NewTabPageWelcomeView: View {

    var body: some View {
        HStack(spacing: Metrics.logoToTextSpacing) {
            Image("Logo")
                .resizable()
                .frame(width: Metrics.logoSize, height: Metrics.logoSize)
            // Proof-of-concept copy, not yet localized.
            Text(verbatim: "Browse anything, tracker-free.")
                .daxTitle2()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(width: Metrics.textWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.bottom, Metrics.bottomPadding)
        .padding(.horizontal, Metrics.horizontalMargin)
    }
}

private enum Metrics {
    static let horizontalMargin: CGFloat = 16
    static let horizontalPadding: CGFloat = 10
    static let bottomPadding: CGFloat = 12
    static let logoSize: CGFloat = 64
    static let logoToTextSpacing: CGFloat = 16
    static let textWidth: CGFloat = 178
}

#Preview {
    NewTabPageWelcomeView()
}
