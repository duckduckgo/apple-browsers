//
//  NewPermissionAuthorizationSwiftUIView.swift
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

import DesignResourcesKitIcons
import SwiftUI

struct NewPermissionAuthorizationSwiftUIView: View {
    private enum Constants {
        static let width: CGFloat = 252
        static let buttonHeight: CGFloat = 32
        static let closeButtonSize: CGFloat = 20
    }

    @ObservedObject
    var viewModel: NewPermissionAuthorizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                Text(viewModel.viewState.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: { viewModel.send(action: .dismiss) }) {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
                        .frame(width: Constants.closeButtonSize, height: Constants.closeButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 4))
                .padding(2)
                .accessibilityLabel(UserText.close)
                .accessibilityIdentifier(viewModel.viewState.closeButtonAccessibilityIdentifier)
            }

            VStack(spacing: 8) {
                ForEach(viewModel.viewState.decisionButtons) { button in
                    decisionButton(button)
                }
            }

            if let learnMore = viewModel.viewState.learnMore {
                Button(action: { viewModel.send(action: .learnMore) }) {
                    Text(learnMore.title)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .accentTextPrimary))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(PlainButtonStyle())
                .cursor(.pointingHand)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: Constants.width)
        .background(Color(designSystemColor: .surfaceSecondary))
        .onAppear {
            viewModel.send(action: .onAppear)
        }
    }

    private func decisionButton(_ button: NewPermissionAuthorizationViewState.DecisionButton) -> some View {
        Button(action: { viewModel.send(action: button.action) }) {
            Text(button.title)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(maxWidth: .infinity)
                .frame(height: Constants.buttonHeight)
                .background(Color(designSystemColor: .controlsFillPrimary))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(button.accessibilityIdentifier)
    }
}

#if DEBUG
@MainActor
private func previewViewModel(domain: String, permissions: [PermissionType]) -> NewPermissionAuthorizationViewModel {
    let query = PermissionAuthorizationQuery(domain: domain, url: URL(string: "https://\(domain)"), permissions: permissions) { _ in }
    return NewPermissionAuthorizationViewModel(query: query, pixelFiring: nil, openURL: { _ in }, finish: {})
}

#Preview("Notifications - Light") {
    NewPermissionAuthorizationSwiftUIView(viewModel: previewViewModel(domain: "microsoft.ai", permissions: [.notification]))
        .preferredColorScheme(.light)
}

#Preview("Location - Dark") {
    NewPermissionAuthorizationSwiftUIView(viewModel: previewViewModel(domain: "maps.example.com", permissions: [.geolocation]))
        .preferredColorScheme(.dark)
}

#Preview("Camera and Microphone") {
    NewPermissionAuthorizationSwiftUIView(viewModel: previewViewModel(domain: "meet.example.com", permissions: [.camera, .microphone]))
}
#endif
