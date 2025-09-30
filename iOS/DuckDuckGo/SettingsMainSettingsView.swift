//
//  SettingsMainSettingsView.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import SyncUI_iOS
import DesignResourcesKit
import DesignResourcesKitIcons

/// This is the main settings view in the app. Please note
/// * General will remain at the top of the list
/// * Other entries are sorted by their translated label - as such follow the existing implementation pattern for your new entry unless you have a really good reason not have it sorted automatically.
struct SettingsMainSettingsView: View {

    struct SettingsEntry {

        let label: String

        // Allow returning nil so that the view builder can just skip "no view"
        let build: (SettingsViewModel) -> AnyView?

    }

    @EnvironmentObject var viewModel: SettingsViewModel

    static let viewBuilder = SettingsViewBuilder()

    let settingsArrangement: [SettingsEntry] = [
        SettingsEntry(label: UserText.settingsAiFeatures, build: Self.viewBuilder.buildAIFeatures),
        SettingsEntry(label: UserText.settingsAppearanceSection, build: Self.viewBuilder.buildAppearence),
        SettingsEntry(label: UserText.settingsSync, build: Self.viewBuilder.buildSyncEntry),
        SettingsEntry(label: UserText.settingsLogins, build: Self.viewBuilder.buildPasswords),
        SettingsEntry(label: UserText.accessibility, build: Self.viewBuilder.buildAccessibility),
        SettingsEntry(label: UserText.dataClearing, build: Self.viewBuilder.buildDataClearing),
        SettingsEntry(label: UserText.duckPlayerFeatureName, build: Self.viewBuilder.buildDuckPlayer),
    ].sorted(by: { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending })

    var body: some View {
        Section(header: Text(UserText.mainSettings)) {
            // General always stays at the top
            NavigationLink(destination: SettingsGeneralView().environmentObject(viewModel)) {
                SettingsCellView(label: UserText.general,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.settings))
            }

            // The rest of settings comes from this array which is sorted by localised label
            ForEach(settingsArrangement, id: \.label) { entry in
                entry.build(viewModel)
            }
        }

    }

    @MainActor
    struct SettingsViewBuilder {

        @ViewBuilder func buildAIFeatures(viewModel: SettingsViewModel) -> AnyView {
            AnyView(NavigationLink(destination: SettingsAIFeaturesView().environmentObject(viewModel)) {
                SettingsCellView(label: UserText.settingsAiFeatures,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.aiGeneral))
            })
        }

        @ViewBuilder func buildAppearence(viewModel: SettingsViewModel) -> AnyView {
            AnyView(NavigationLink(destination: SettingsAppearanceView().environmentObject(viewModel)) {
                SettingsCellView(label: UserText.settingsAppearanceSection,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.appearance))
            })
        }

        @ViewBuilder func buildAccessibility(viewModel: SettingsViewModel) -> AnyView {
            AnyView(NavigationLink(destination: SettingsAccessibilityView().environmentObject(viewModel)) {
                SettingsCellView(label: UserText.accessibility,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.accessibility))
            })
        }

        @ViewBuilder func buildDataClearing(viewModel: SettingsViewModel) -> AnyView {
            AnyView(NavigationLink(destination: SettingsDataClearingView().environmentObject(viewModel)) {
                SettingsCellView(label: UserText.dataClearing,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.fire))
            })
        }

        @ViewBuilder func buildDuckPlayer(viewModel: SettingsViewModel) -> AnyView? {
            if viewModel.state.duckPlayerEnabled {
                AnyView(NavigationLink(destination: SettingsDuckPlayerView().environmentObject(viewModel)) {
                    SettingsCellView(label: UserText.duckPlayerFeatureName,
                                     image: Image(uiImage: DesignSystemImages.Color.Size24.videoPlayer))
                })
            }
        }

        @ViewBuilder func buildSyncEntry(viewModel: SettingsViewModel) -> AnyView {
            let statusIndicator = viewModel.syncStatus == .on ? StatusIndicatorView(status: viewModel.syncStatus, isDotHidden: true) : nil
            let label = viewModel.state.sync.title
            AnyView(SettingsCellView(label: label,
                             image: Image(uiImage: DesignSystemImages.Color.Size24.sync1),
                             action: { viewModel.presentLegacyView(.sync(nil)) },
                             statusIndicator: statusIndicator,
                             disclosureIndicator: true,
                             isButton: true))
        }

        @ViewBuilder func buildPasswords(viewModel: SettingsViewModel) -> AnyView {
            AnyView(SettingsCellView(label: UserText.settingsLogins,
                             image: Image(uiImage: DesignSystemImages.Color.Size24.key),
                             action: { viewModel.presentLegacyView(.autofill) },
                             disclosureIndicator: true,
                             isButton: true))
        }

    }

}
