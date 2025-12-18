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
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                (Text(model.title).fontWeight(.semibold) + Text(" " + model.subtitle))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
                Spacer()

                Button(action: { model.onInfo() }, label: {
                    Image(uiImage: UIImage(resource: .infoIcon))
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(Color(designSystemColor: .iconsSecondary))
                        .padding(8)
                })
                .accessibilityLabel(Text(UserText.tabSwitcherTrackerCountInfoA11y))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
                         subtitle: "in last 7 days",
                         icon: UIImage(resource: .trackerShield),
                         accentColor: Color(designSystemColor: .accent),
                         backgroundColor: .green0,
                         onTap: {},
                         onInfo: {})
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
