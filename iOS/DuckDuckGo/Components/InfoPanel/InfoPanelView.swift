//
//  InfoPanelView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DesignResourcesKitIcons

struct InfoPanelView: View {

    struct Model {
        let title: String
        let subtitle: String
        let icon: UIImage
        let accentColor: Color
        let backgroundColor: Color
        let onTap: () -> Void
        let onInfo: () -> Void
    }

    let model: Model

    var body: some View {
        Button(action: { model.onTap() }, label: {
            HStack(spacing: 12) {
                Image(uiImage: model.icon)
                    .renderingMode(.template)
                    .foregroundColor(model.accentColor)
                    .padding(10)
                    .background(model.accentColor.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(model.subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                Spacer()

                Button(action: { model.onInfo() }, label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .padding(8)
                })
                .accessibilityLabel(Text(UserText.tabSwitcherTrackerCountInfoA11y))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(model.backgroundColor)
            )
        })
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct InfoPanelView_Previews: PreviewProvider {
    static var previews: some View {
        InfoPanelView(
            model: .init(title: "396 trackers blocked",
                         subtitle: "in the last week",
                         icon: UIImage(resource: .shieldDot),
                         accentColor: Color(designSystemColor: .accent),
                         backgroundColor: Color(designSystemColor: .surface),
                         onTap: {},
                         onInfo: {})
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
