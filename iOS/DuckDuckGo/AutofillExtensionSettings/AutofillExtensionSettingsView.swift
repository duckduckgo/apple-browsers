//
//  AutofillExtensionSettingsView.swift
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

@available(iOS 18.0, *)
struct AutofillExtensionSettingsView: View {

    @ObservedObject var viewModel: AutofillExtensionSettingsViewModel

    var body: some View {
        List {
            Section(header: HeaderView(isExtensionEnabled: viewModel.isExtensionEnabled),
                    footer: Text(UserText.autofillExtensionFooter)) {
                if viewModel.isExtensionEnabled {
                    Button {
                        Task { await viewModel.disableExtension() }
                    } label: {
                        HStack {
                            Text(UserText.autofillExtensionTurnOffButtonTitle)
                                .daxBodyRegular()
                                .foregroundStyle(Color(designSystemColor: .accent))
                            Spacer()
                            Image(uiImage: DesignSystemImages.Glyphs.Size16.openIn)
                                .foregroundStyle(Color(designSystemColor: .iconsTertiary))
                        }
                    }
                } else {
                    Button {
                        Task { await viewModel.enableExtension() }
                    } label: {
                        Text(UserText.autofillExtensionTurnOnButtonTitle)
                            .daxBodyRegular()
                            .foregroundStyle(Color(designSystemColor: .accent))
                    }
                }

            }
            .listRowBackground(Color(designSystemColor: .surface))
        }
        .applyInsetGroupedListStyle()
        .sheet(isPresented: $viewModel.isShowingActivationView) {
            AutofillExtensionSettingsActivationView()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.updateExtensionStatus() }
        }
    }

    private struct HeaderView: View {
        let isExtensionEnabled: Bool

        @ViewBuilder
        var body: some View {
            if isExtensionEnabled {
                HStack(spacing: 6) {
                    Text(UserText.autofillExtensionHeaderEnabled)
                    Circle()
                        .fill(Color(designSystemColor: .alertGreen))
                        .frame(width: 8, height: 8)
                }
            } else {
                Text(UserText.autofillExtensionHeaderDisabled)
            }
        }
    }
}
