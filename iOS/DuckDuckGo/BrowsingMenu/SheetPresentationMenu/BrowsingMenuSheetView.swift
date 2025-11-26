//
//  BrowsingMenuSheetView.swift
//  DuckDuckGo
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
import UIKit
import DesignResourcesKit
import DesignResourcesKitIcons

typealias BrowsingMenuSheetViewController = UIHostingController<BrowsingMenuSheetView>

struct BrowsingMenuSheetView: View {

    @Environment(\.presentationMode) var presentationMode

    private let headerItems: [BrowsingMenuEntry.EntryData]
    private let sections: [MenuSection]
    private let onDismiss: () -> Void

    @State private var actionToPerform: () -> Void

    init(headerItems: [BrowsingMenuEntry], listItems: [BrowsingMenuEntry], onDismiss: @escaping () -> Void) {
        self.headerItems = headerItems.compactMap(\.entryData)
        self.sections = listItems.split(whereSeparator: \.isSeparator).map { MenuSection(items: $0.compactMap(\.entryData)) }
        self.onDismiss = onDismiss
        self.actionToPerform = { }
    }

    var body: some View {

        List {
            Section {
                if !headerItems.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(headerItems) { headerItem in
                            MenuHeaderButton(entryData: headerItem) {
                                actionToPerform = { headerItem.action() }
                                presentationMode.wrappedValue.dismiss()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .background((Color(designSystemColor: .background)))
                }
            }
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))

            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        MenuRowButton(entryData: item) {
                            actionToPerform = { item.action() }
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
        }
        .applyInsetGroupedListStyle()
        .onDisappear(perform: {
            actionToPerform()
            onDismiss()
        })
        .tint(Color(designSystemColor: .textPrimary))
    }
}

private struct MenuSection: Identifiable {
    let id = UUID()
    let items: [BrowsingMenuEntry.EntryData]
}

private struct MenuRowButton: View {

    fileprivate let entryData: BrowsingMenuEntry.EntryData
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(uiImage: entryData.image)
                Text(entryData.name)

                if entryData.showNotificationDot {
                    Circle().fill(entryData.customDotColor.map({ Color($0) }) ?? Color(designSystemColor: .accent))
                        .frame(width: 8, height: 8)
                        .padding(.leading, 6)
                        .padding(.trailing, 12)

                    Spacer()
                }
            }
        }
        .accessibilityLabel(entryData.accessibilityLabel ?? entryData.name)
    }
}

private struct MenuHeaderButton: View {

    fileprivate let entryData: BrowsingMenuEntry.EntryData
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(uiImage: entryData.image)
                    .tint(Color(designSystemColor: .icons))
                Text(entryData.name)
                    .daxFootnoteRegular()
                    .foregroundStyle(Color(designSystemColor: .textSecondary))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: Constant.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: Constant.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entryData.accessibilityLabel ?? entryData.name)
    }

    private enum Constant {
        static let cornerRadius: CGFloat = 4
    }

}

private extension BrowsingMenuEntry {
    var isSeparator: Bool {
        switch self {
        case .separator: return true
        default: return false
        }
    }

    var entryData: EntryData? {
        switch self {
        case .separator: return nil
        case .regular(let name, let accessibilityLabel, let image, let showNotificationDot, let customDotColor, let action):
            return EntryData(name: name, accessibilityLabel: accessibilityLabel, image: image, showNotificationDot: showNotificationDot, customDotColor: customDotColor, action: action)
        }
    }

    struct EntryData: Identifiable, Equatable {
        let id: UUID = UUID()
        let name: String
        let accessibilityLabel: String?
        let image: UIImage
        let showNotificationDot: Bool
        let customDotColor: UIColor?
        let action: () -> Void

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: BrowsingMenuEntry.EntryData, rhs: BrowsingMenuEntry.EntryData) -> Bool {
            lhs.id == rhs.id
        }
    }
}
