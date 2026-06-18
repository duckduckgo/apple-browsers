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

/// Renders a full remote-message card for every `RemotePlaceholder`, so the rebranded artwork can
/// be reviewed in its real message UI rather than as a bare image. The artwork picker switches
/// between the live `appRebranding` flag, the legacy artwork (`<name>-legacy`) and the rebranded
/// artwork (`<name>`); the chosen image is supplied as the message's preloaded image, so the
/// preview never mutates the global rebrand flag.
struct RemoteMessagingUIPreviewsDebugView: View {

    enum ArtworkMode: String, CaseIterable, Identifiable {
        case live = "Live (flag)"
        case legacy = "Legacy"
        case rebranded = "Rebranded"
        var id: String { rawValue }
    }

    @State private var artworkMode: ArtworkMode = .live

    private let placeholders: [RemotePlaceholder] = RemotePlaceholder.allCases
        .filter { UIImage(named: $0.rawValue) != nil || UIImage(named: "\($0.rawValue)-legacy") != nil }
        .sorted { $0.rawValue < $1.rawValue }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Artwork", selection: $artworkMode) {
                ForEach(ArtworkMode.allCases) { mode in
                    Text(verbatim: mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                LazyVStack(spacing: 28) {
                    ForEach(placeholders, id: \.self) { placeholder in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: placeholder.rawValue)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(baseColor: .gray70))
                            HomeMessageView(viewModel: viewModel(for: placeholder))
                                .id("\(placeholder.rawValue)-\(artworkMode.rawValue)")
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("RMF UI previews")
    }

    private func viewModel(for placeholder: RemotePlaceholder) -> HomeMessageViewModel {
        HomeMessageViewModel(
            messageId: "preview-\(placeholder.rawValue)",
            modelType: .bigSingleAction(
                titleText: placeholder.rawValue,
                descriptionText: "Sample remote message body used to preview the artwork inside a full message card.",
                placeholder: placeholder,
                imageUrl: nil,
                primaryActionText: "Primary Action",
                primaryAction: .appStore
            ),
            messageActionHandler: NoOpRemoteMessagingActionHandler(),
            preloadedImage: image(for: placeholder),
            loadRemoteImage: nil,
            onDidClose: { _ in },
            onDidAppear: {},
            onAttachAdditionalParameters: nil
        )
    }

    private func image(for placeholder: RemotePlaceholder) -> UIImage? {
        let name = placeholder.rawValue
        switch artworkMode {
        case .live:
            return UIImage(rebrandable: name)
        case .legacy:
            return UIImage(named: "\(name)-legacy") ?? UIImage(named: name)
        case .rebranded:
            return UIImage(named: name)
        }
    }
}

private final class NoOpRemoteMessagingActionHandler: RemoteMessagingActionHandling {
    func handleAction(_ remoteAction: RemoteAction, context: PresentationContext) async {}
}
