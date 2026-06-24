//
//  RemoteMessagingUIPreviewsDebugView.swift
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

import SwiftUI
import UIKit
import RemoteMessaging
import DesignResourcesKit
import DesignResourcesKitIcons

/// Renders one full remote-message card per supported message type, so each layout can be reviewed in its real message UI.
/// 
struct RemoteMessagingUIPreviewsDebugView: View {

    private let samples: [(name: String, modelType: HomeSupportedMessageDisplayType)] = [
        ("small", .small(titleText: "Small",
                          descriptionText: "Description")),
        ("medium", .medium(titleText: "Medium",
                            descriptionText: "Description text",
                            placeholder: .criticalUpdate,
                            imageUrl: nil)),
        ("bigSingleAction", .bigSingleAction(titleText: "Big Single",
                                             descriptionText: "This is a description",
                                             placeholder: .ddgAnnounce,
                                             imageUrl: nil,
                                             primaryActionText: "Primary",
                                             primaryAction: .dismiss)),
        ("bigTwoAction", .bigTwoAction(titleText: "Big Two",
                                       descriptionText: "This is a <b>big</b> two style",
                                       placeholder: .macComputer,
                                       imageUrl: nil,
                                       primaryActionText: "App Store",
                                       primaryAction: .appStore,
                                       secondaryActionText: "Dismiss",
                                       secondaryAction: .dismiss)),
        ("promoSingleAction", .promoSingleAction(titleText: "Promotional",
                                                 descriptionText: "Description <b>with bold</b> to make a statement.",
                                                 placeholder: .newForMacAndWindows,
                                                 imageUrl: nil,
                                                 actionText: "Share",
                                                 action: .share(value: "value", title: "title")))
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                ForEach(samples, id: \.name) { sample in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: sample.name)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(baseColor: .gray70))
                        HomeMessageView(viewModel: viewModel(id: sample.name, modelType: sample.modelType))
                    }
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("RMF UI previews")
    }

    private func viewModel(id: String, modelType: HomeSupportedMessageDisplayType) -> HomeMessageViewModel {
        HomeMessageViewModel(
            messageId: "preview-\(id)",
            modelType: modelType,
            messageActionHandler: NoOpRemoteMessagingActionHandler(),
            preloadedImage: previewImage(for: modelType),
            loadRemoteImage: nil,
            onDidClose: { _ in },
            onDidAppear: {},
            onAttachAdditionalParameters: nil
        )
    }

    /// Supplies the placeholder artwork for types that have one; `.small` has no pictogram.
    private func previewImage(for modelType: HomeSupportedMessageDisplayType) -> UIImage? {
        switch modelType {
        case .small:
            return nil
        case .medium(_, _, let placeholder, _),
             .bigSingleAction(_, _, let placeholder, _, _, _),
             .bigTwoAction(_, _, let placeholder, _, _, _, _, _),
             .promoSingleAction(_, _, let placeholder, _, _, _):
            return UIImage(rebrandable: placeholder.rawValue)
        }
    }
}

private final class NoOpRemoteMessagingActionHandler: RemoteMessagingActionHandling {
    func handleAction(_ remoteAction: RemoteAction, context: PresentationContext) async {}
}
