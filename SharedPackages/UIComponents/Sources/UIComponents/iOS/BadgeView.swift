//
//  BadgeView.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit

public struct BadgeView: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.caption2)
            .bold()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(designSystemColor: .alertYellow))
            .foregroundColor(.black)
            .cornerRadius(6)
    }
}

#if DEBUG

private struct BadgeViewPreviewSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BadgeView(text: "New")
            BadgeView(text: "Try for Free")
            HStack {
                Text("VPN")
                Spacer()
                BadgeView(text: "Try for Free")
            }
        }
        .padding()
    }
}

#Preview("Light") {
    BadgeViewPreviewSamples()
}

#Preview("Dark") {
    BadgeViewPreviewSamples()
        .preferredColorScheme(.dark)
}

#endif

#endif
