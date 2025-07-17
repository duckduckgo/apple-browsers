//
//  SettingsOthersView.swift
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
import Networking
import DesignResourcesKit
import DesignResourcesKitIcons
import Common

struct SettingsOthersView: View {

    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            // About
            NavigationLink(destination: AboutView().environmentObject(viewModel)) {
#if (ALPHA && !DEBUG)
                // The commit SHA is only set for release alpha builds, so debug alpha builds won't show it
                let version = "v\(viewModel.state.version) (\(AppVersion.shared.commitSHAShort))"
#else
                let version = "v\(viewModel.state.version)"
#endif

                SettingsCellView(label: UserText.settingsAboutSection,
                                 image: Image(.logoIcon),
                                 accessory: .rightDetail(version))
            }

            // Share Feedback
            if viewModel.enablesUnifiedFeedbackForm {
                let formViewModel = UnifiedFeedbackFormViewModel(subscriptionManager: AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
                                                                 apiService: DefaultAPIService(),
                                                                 vpnMetadataCollector: DefaultVPNMetadataCollector(),
                                                                 isPaidAIChatFeatureEnabled: { AppDependencyProvider.shared.featureFlagger.isFeatureOn(.paidAIChat) },
                                                                 source: .settings)
                NavigationLink {
                    UnifiedFeedbackCategoryView(UserText.subscriptionFeedback, options: UnifiedFeedbackFlowCategory.allCases, selection: $viewModel.selectedFeedbackFlow) {
                        if let selectedFeedbackFlow = viewModel.selectedFeedbackFlow {
                            switch UnifiedFeedbackFlowCategory(rawValue: selectedFeedbackFlow) {
                            case nil:
                                EmptyView()
                            case .browserFeedback:
                                LegacyFeedbackView()
                            case .ppro:
                                UnifiedFeedbackRootView(viewModel: formViewModel)
                            }
                        }
                    }
                    .onFirstAppear {
                        Task {
                            await formViewModel.process(action: .reportShow)
                        }
                    }
                } label: {
                    SettingsCellView(label: UserText.subscriptionFeedback,
                                     image: Image(uiImage: DesignSystemImages.Color.Size24.feedback))
                }
            } else {
                SettingsCellView(label: UserText.settingsFeedback,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.feedback),
                                 action: { viewModel.presentLegacyView(.feedback) },
                                 isButton: true)
            }

            // DuckDuckGo on Other Platforms
            SettingsCellView(label: UserText.duckduckgoOnOtherPlatforms,
                             image: Image(uiImage: DesignSystemImages.Color.Size24.downloads),
                             action: { viewModel.openOtherPlatforms() },
                             webLinkIndicator: true,
                             isButton: true)
        }
    }

}

private struct LegacyFeedbackView: View {
    var body: some View {
        LegacyFeedbackViewRepresentable()
    }
}

// swiftlint:disable force_cast
private struct LegacyFeedbackViewRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> some UIViewController {
        let storyboard = UIStoryboard(name: "Feedback", bundle: nil)
        let navigationController = storyboard.instantiateViewController(withIdentifier: "Feedback") as! UINavigationController
        return navigationController.viewControllers.first!
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }
}
// swiftlint:enable force_cast
