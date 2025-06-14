//
//  SettingsCompleteSetupView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons

@available(iOS 18.2, *)
struct SettingsCompleteSetupView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    private var swipeColor: Color {
        switch colorScheme {
        case .light:
            Color(red: 0.875, green: 0.875, blue: 0.875)
        case .dark:
            Color(red: 0.255, green: 0.255, blue: 0.255)
        @unknown default:
            Color(red: 0.875, green: 0.875, blue: 0.875)
        }
    }
    
    var body: some View {
        Section(header: Text(UserText.completeSetupSettings)) {
            // Set As Default Browser
            if viewModel.shouldShowSetAsDefaultBrowser {
                SettingsCellView(label: UserText.setAsDefaultBrowser,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.defaultBrowserMobile),
                                 action: { viewModel.setAsDefaultBrowser("complete-setup") },
                                 webLinkIndicator: true,
                                 isButton: true)
                .swipeActions {
                    Button {
                        viewModel.dismissSetAsDefaultBrowser()
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.eyeClosed
                            .withTintColor(UIColor(designSystemColor: .textPrimary), renderingMode: .alwaysOriginal))
                    }
                    .tint(Color(swipeColor))
                }
                .id(colorScheme)
            }

            // Passwords Import
            if viewModel.shouldShowImportPasswords {
                SettingsCellView(label: UserText.importPasswords,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.keyImport),
                                 action: { viewModel.presentLegacyView(.passwordsImport) },
                                 disclosureIndicator: true,
                                 isButton: true)
                .swipeActions {
                    Button {
                        viewModel.dismissImportPasswords()
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.eyeClosed
                            .withTintColor(UIColor(designSystemColor: .textPrimary), renderingMode: .alwaysOriginal))
                    }
                    .tint(Color(swipeColor))
                }
                .id(colorScheme)
            }
        }
    }
}
