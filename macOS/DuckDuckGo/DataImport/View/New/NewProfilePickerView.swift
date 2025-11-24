//
//  NewProfilePickerView.swift
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

import Foundation
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import BrowserServicesKit

struct NewProfilePickerView: View {
    @StateObject var viewModel: ProfilePickerViewModel
    @Environment(\.dismiss) private var dismiss

    init(profiles: [DataImport.BrowserProfile], selectedProfile: DataImport.BrowserProfile?, updateSelectedProfile: @escaping (DataImport.BrowserProfile) -> Void) {
        _viewModel = .init(wrappedValue: .init(profiles: profiles, selectedProfile: selectedProfile, updateSelectedProfile: updateSelectedProfile))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.importSelectProfileTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.top, 20)
                .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.items.indices, id: \.self) { index in
                    HStack(alignment: .center, spacing: 8) {
                        Image(nsImage: DesignSystemImages.Glyphs.Size24.check)
                            .renderingMode(.template)
                            .foregroundColor(.accentColor)
                            .opacity(viewModel.items[index].isSelected ? 1 : 0)
                            .frame(width: 20, height: 20).padding(.vertical, 4)

                        Image(nsImage: viewModel.items[index].icon ?? DesignSystemImages.Color.Size24.document)
                            .frame(width: 24, height: 24).padding(4)
                        HStack(spacing: 6) {
                            Text(viewModel.items[index].title)
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.didSelect(viewModel.items[index])
                    }

                    if index < viewModel.items.count - 1 {
                        Divider()
                            .foregroundColor(.secondary)
                    }
                }
            }
            .borderedBackground()
        }
        .padding(20)
    }
}

@MainActor
final class ProfilePickerViewModel: ObservableObject {
    struct ProfileItem: Identifiable {
        fileprivate let profile: DataImport.BrowserProfile
        var id: String {
            profile.profileURL.absoluteString
        }

        var title: String {
            profile.profileName
        }

        var subtitle: String {
            profile.profileURL.lastPathComponent
        }

        var icon: NSImage? {
            profile.browser.applicationIcon
        }

        var isSelected: Bool = false

        init(profile: DataImport.BrowserProfile, isSelected: Bool = false) {
            self.profile = profile
            self.isSelected = isSelected
        }
    }

    @Published var items: [ProfileItem]
    @Published var isContinueDisabled: Bool = true
    let updateSelectedProfile: (DataImport.BrowserProfile) -> Void

    init(profiles: [DataImport.BrowserProfile], selectedProfile: DataImport.BrowserProfile?, updateSelectedProfile: @escaping (DataImport.BrowserProfile) -> Void) {
        self.items = profiles.map { ProfileItem(profile: $0, isSelected: $0 == selectedProfile) }
        self.updateSelectedProfile = updateSelectedProfile
    }

    func didSelect(_ item: ProfileItem) {
        self.items = items.map {
            .init(profile: $0.profile, isSelected: item.id == $0.id)
        }
        updateSelectedProfile(item.profile)
    }
}
