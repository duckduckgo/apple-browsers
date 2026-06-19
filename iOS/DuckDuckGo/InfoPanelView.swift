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

    private enum Constants {
        static let contentSpacing: CGFloat = 6
        static let iconSize: CGFloat = 18
        static let infoButtonPadding: CGFloat = 4
        static let maxWidth: CGFloat = 480

        static let legacyHorizontalPadding: CGFloat = 10
        static let legacyVerticalPadding: CGFloat = 8
        static let legacyCornerRadius: CGFloat = 16

        static let rebrandedHorizontalPadding: CGFloat = 16
        static let rebrandedHeight: CGFloat = 48
        static let rebrandedCornerRadius: CGFloat = 26
    }

    struct Model {
        let title: String
        let subtitle: String
        let icon: UIImage
        let backgroundColor: Color
        let onTap: () -> Void
        let onInfo: () -> Void
    }

    let model: Model

    private var isRebranded: Bool { AppRebrand.isAppRebranded() }
    private var cornerRadius: CGFloat { isRebranded ? Constants.rebrandedCornerRadius : Constants.legacyCornerRadius }
    private var horizontalPadding: CGFloat { isRebranded ? Constants.rebrandedHorizontalPadding : Constants.legacyHorizontalPadding }
    private var subtitleColor: Color { Color(designSystemColor: isRebranded ? .textSecondary : .textPrimary) }
    private var infoIconColor: Color { Color(designSystemColor: isRebranded ? .iconsTertiary : .iconsSecondary) }

    var body: some View {
        HStack(alignment: .center, spacing: Constants.contentSpacing) {
            Image(uiImage: model.icon)
                .resizable()
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .accessibilityHidden(true)

            (Text(model.title).fontWeight(.semibold)
                .foregroundColor(Color(designSystemColor: .textPrimary))
             + Text(" " + model.subtitle)
                .foregroundColor(subtitleColor))
                .font(.subheadline)
            Spacer()

            Button(action: { model.onInfo() }, label: {
                Image(uiImage: UIImage(resource: .infoIcon))
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .foregroundColor(infoIconColor)
                    .padding(Constants.infoButtonPadding)
            })
            .accessibilityLabel(Text(UserText.tabSwitcherTrackerCountInfoA11y))
            .accessibilityHint(Text(UserText.tabSwitcherTrackerCountInfoHintA11y))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, isRebranded ? 0 : Constants.legacyVerticalPadding)
        .frame(height: isRebranded ? Constants.rebrandedHeight : nil)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(model.backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture { model.onTap() }
        .frame(maxWidth: Constants.maxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.title + " " + model.subtitle))
    }
}

// MARK: - Tracker Info Panel Model Factory

extension InfoPanelView.Model {

    /// Creates a model configured for displaying tracker count information in the tab switcher.
    /// - Parameters:
    ///   - state: The current state from the tracker count view model
    ///   - onTap: Action to perform when the panel is tapped
    ///   - onInfo: Action to perform when the info button is tapped
    /// - Returns: A configured InfoPanelView.Model for tracker info display
    static func trackerInfoPanel(
        state: TabSwitcherTrackerCountViewModel.State,
        onTap: @escaping () -> Void,
        onInfo: @escaping () -> Void
    ) -> InfoPanelView.Model {
        return InfoPanelView.Model(
            title: state.title,
            subtitle: state.subtitle,
            icon: UIImage(rebrandable: "TrackerShield") ?? UIImage(resource: .trackerShield),
            backgroundColor: AppRebrand.isAppRebranded()
                ? Color(designSystemColor: .surfaceSecondary)
                : Color(singleUseColor: .tabSwitcherTrackerCountBackground),
            onTap: onTap,
            onInfo: onInfo
        )
    }
}

#if DEBUG
struct InfoPanelView_Previews: PreviewProvider {
    static var previews: some View {
        InfoPanelView(
            model: .init(title: "396 trackers blocked",
                         subtitle: "in the last 7 days",
                         icon: UIImage(rebrandable: "TrackerShield") ?? UIImage(resource: .trackerShield),
                         backgroundColor: Color(singleUseColor: .tabSwitcherTrackerCountBackground),
                         onTap: {},
                         onInfo: {})
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
