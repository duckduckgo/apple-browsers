//
//  SyncPromoView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import DuckUI
import MetricBuilder

#if DEBUG
import PreviewSnapshots
#endif

struct SyncPromoView: View {

    let viewModel: SyncPromoViewModel
    @State private var isAccessibilityHidden = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Group {
                    Image(viewModel.image)
                        .scaledToFit()
                        .accessibilityHidden(true)
                    
                    Text(viewModel.title)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity)
                        .daxHeadline()
                    Text(viewModel.subtitle)
                        .daxSubheadRegular()
                        .foregroundColor(subtitleColor)
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: ButtonStackMetrics.interButtonSpacing) {
                    if let secondaryButtonTitle = viewModel.secondaryButtonTitle {
                        Button {
                            viewModel.dismissButtonAction?()
                        } label: {
                            Text(secondaryButtonTitle)
                        }
                        .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: true))
                        .accessibilityLabel(secondaryButtonTitle)
                    }

                    primaryButton
                        .accessibilityLabel(viewModel.primaryButtonTitle)
                }
                .padding(.top, 12)
            }
            .multilineTextAlignment(.center)
            .padding(.top)
            .padding(.bottom, ButtonStackMetrics.containerPadding)
            .padding(.horizontal, ButtonStackMetrics.containerPadding)

            Button {
                viewModel.dismissButtonAction?()
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
            }
            .buttonStyle(CloseButtonStyle())
            .padding(ContainerMetrics.closeButtonPadding - CloseButtonStyle.Constant.padding)
            .accessibilityHidden(true)
        }
        .background(
            RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius)
                .foregroundColor(Color(designSystemColor: .surfaceTertiary))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .accessibilityHidden(isAccessibilityHidden)
        .onAppear {
            // Delay accessibility activation for maestro
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isAccessibilityHidden = false
            }
        }
    }

    private var subtitleColor: Color? {
        switch viewModel.design {
        case .standard:
            nil
        case .redesigned:
            Color(designSystemColor: .textSecondary)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let button = Button {
            viewModel.primaryButtonAction?()
        } label: {
            Text(viewModel.primaryButtonTitle)
        }

        switch viewModel.design {
        case .standard:
            button.buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: true))
        case .redesigned:
            button.buttonStyle(BrandButtonStyle(compact: true, fullWidth: true))
        }
    }
}

#if DEBUG
struct SyncPromoView_Previews: PreviewProvider {

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots(configurations: [
        .init(name: "Standard", state: SyncPromoManager.Design.standard, scope: .previews),
        .init(name: "Redesigned", state: SyncPromoManager.Design.redesigned)
    ]) { design in
        SyncPromoView(viewModel: SyncPromoViewModel(touchpointType: .bookmarks, design: design))
            .background(Color(designSystemColor: .background))
    }
}
#endif
