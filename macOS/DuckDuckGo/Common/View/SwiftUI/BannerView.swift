//
//  BannerView.swift
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
import SwiftUIExtensions

struct TitledButtonAction {
    let title: String
    let action: () -> Void
}

final class BannerMessageViewController: NSHostingController<BannerView> {
    let viewModel: BannerViewModel

    init(message: String,
         image: NSImage,
         primaryAction: TitledButtonAction,
         secondaryAction: TitledButtonAction?,
         closeAction: @escaping () -> Void) {
        self.viewModel = .init(message: message,
                               image: image,
                               primaryAction: primaryAction,
                               secondaryAction: secondaryAction,
                               closeAction: closeAction)

        super.init(rootView: BannerView(viewModel: viewModel))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BannerViewModel: ObservableObject {
    @Published var message: String
    @Published var image: NSImage
    @Published var primaryAction: TitledButtonAction
    @Published var secondaryAction: TitledButtonAction?
    @Published var closeAction: () -> Void

    public init(message: String,
                image: NSImage,
                primaryAction: TitledButtonAction,
                secondaryAction: TitledButtonAction?,
                closeAction: @escaping () -> Void) {
        self.message = message
        self.image = image
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.closeAction = closeAction
    }
}

struct BannerView: View {
    @ObservedObject public var viewModel: BannerViewModel

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(nsImage: viewModel.image)

                Text(viewModel.message)

                mainActionButtons

                Spacer()

                HoverButton(image: .closeLarge, cornerRadius: 6) {
                    viewModel.closeAction()
                }
                .padding(.trailing, 10)
            }
            .padding(.leading, 19)

            Spacer()

            Divider()
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .background(Color.bannerViewDivider.opacity(0.09))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.bannerBackground)
    }

    private var mainActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.primaryAction.action()
            } label: {
                Text(viewModel.primaryAction.title)
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: true))

            if let secondaryAction = viewModel.secondaryAction {
                Button {
                    secondaryAction.action()
                } label: {
                    Text(secondaryAction.title)
                }
                .buttonStyle(DismissActionButtonStyle())
            }
        }
    }
}
