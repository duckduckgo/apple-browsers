//
//  SettingsAutoplayView.swift
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

import Core
import SwiftUI

struct SettingsAutoplayView: View {

    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var showDuckPlayerSettings = false

    var body: some View {
        ListBasedPicker(
            title: UserText.settingsAutoplayLabel,
            options: AutoplayBlockingMode.allCases,
            selectedOption: viewModel.autoplayBlockingModeBinding,
            descriptionForOption: { $0.description },
            sectionHeader: UserText.settingsAutoplayLabel
        ) {
            Text(footerAttributedString)
                .environment(\.openURL, OpenURLAction { url in
                    switch FooterAction.from(url) {
                    case .duckPlayerSettings?:
                        showDuckPlayerSettings = true
                        return .handled
                    case nil:
                        return .systemAction
                    }
                })
        }
        .sheet(isPresented: $showDuckPlayerSettings) {
            NavigationView {
                SettingsDuckPlayerView().environmentObject(viewModel)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showDuckPlayerSettings = false
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(Color(designSystemColor: .textPrimary))
                            }
                        }
                    }
            }
        }
        .applySettingsListModifiers(title: "", displayMode: .inline, viewModel: viewModel)
        .onFirstAppear {
            Pixel.fire(pixel: .settingsAutoplayOpen)
        }
    }
}

private extension SettingsAutoplayView {
    var footerAttributedString: AttributedString {
        var base = AttributedString(UserText.settingsAutoplayFooter)
        var link = AttributedString(UserText.settingsAutoplayDuckPlayerLink)
        link.foregroundColor = Color(designSystemColor: .accent)
        link.link = FooterAction.duckPlayerSettings.url
        base.append(link)
        base.append(AttributedString("."))
        return base
    }
}

private enum FooterAction {
    static let scheme = "action"

    case duckPlayerSettings

    var url: URL {
        URL(string: "\(Self.scheme)://\(host)")!
    }

    private var host: String {
        switch self {
        case .duckPlayerSettings: return "duck-player-settings"
        }
    }

    static func from(_ url: URL) -> FooterAction? {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "duck-player-settings": return .duckPlayerSettings
        default: return nil
        }
    }
}
