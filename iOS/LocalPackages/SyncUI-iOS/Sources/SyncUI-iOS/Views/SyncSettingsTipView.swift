//
//  SyncSettingsTipView.swift
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
import DesignResourcesKitIcons
import SwiftUI
import TipKit

@available(iOS 18.0, *)
struct SyncSettingsTip: Tip {
    enum Kind: Sendable {
        case newDevices(Set<String>)
        case notificationPermission
    }

    let kind: Kind
    let titleText: String
    let messageText: String
    let actionText: String

    var id: String {
        switch kind {
        case .newDevices(let eventIDs):
            // A later batch must remain eligible after the user closes an earlier alert.
            return "com.duckduckgo.sync.newDevices." + eventIDs.sorted().joined(separator: ",")
        case .notificationPermission:
            return "com.duckduckgo.sync.notificationPermission"
        }
    }

    var title: Text { Text(titleText) }
    var message: Text? { Text(messageText) }

    var image: Image? {
        let icon = switch kind {
        case .newDevices: DesignSystemImages.Glyphs.Size24.deviceAll
        case .notificationPermission: DesignSystemImages.Glyphs.Size24.bellNotification
        }
        // TipView shares its tint between the icon and action. Keep the icon's accent color.
        let tintedIcon = UIGraphicsImageRenderer(size: icon.size).image { _ in
            let bounds = CGRect(origin: .zero, size: icon.size)
            icon.draw(in: bounds)
            UIColor(designSystemColor: .accentPrimary).setFill()
            UIRectFillUsingBlendMode(bounds, .sourceIn)
        }
        return Image(uiImage: tintedIcon).renderingMode(.original)
    }

    var actions: [Action] {
        [Action(id: "primary") {
            Text(actionText)
                .foregroundStyle(Color(designSystemColor: .buttonsSecondaryFillText))
        }]
    }

    var options: [any TipOption] {
        IgnoresDisplayFrequency(true)
    }
}

@available(iOS 18.0, *)
struct SyncSettingsTipView: View {
    let tip: SyncSettingsTip
    let action: () -> Void
    let dismiss: () -> Void

    var body: some View {
        TipView(tip) { _ in action() }
            .id(tip.id)
            .tipImageSize(CGSize(width: 32, height: 32))
            .tipBackground(Color(designSystemColor: .surfaceTertiary))
            .tint(Color(designSystemColor: .buttonsSecondaryFillDefault))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .task(id: tip.id) {
                for await status in tip.statusUpdates {
                    guard !Task.isCancelled else { return }
                    if case .invalidated(.tipClosed) = status {
                        dismiss()
                        return
                    }
                }
            }
    }
}
