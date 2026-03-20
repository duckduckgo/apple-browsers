//
//  RebrandedAddToDockPromoView.swift
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

import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoView: View {
        private static let videoURL = Bundle.main.url(forResource: "Rebranded-AddToDock-promo", withExtension: "mov")

        private enum Design {
            static let borderWidth: CGFloat = 321
            static let borderHeight: CGFloat = 127
            static let videoWidth: CGFloat = 300
            static let videoHeight: CGFloat = 120
            static let borderHorizontalPadding: CGFloat = -6
        }

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let ratio = width / Design.borderWidth

                ZStack(alignment: .top) {
                    OnboardingRebrandingImages.AddToDock.promoBorder
                        .resizable()
                        .padding(EdgeInsets(top: 0,
                                            leading: Design.borderHorizontalPadding * ratio,
                                            bottom: 0,
                                            trailing: Design.borderHorizontalPadding * ratio))
                        .frame(width: width, height: Design.borderHeight * ratio)
                    if let videoURL = Self.videoURL {
                        AddToDockVideoPlayer(url: videoURL,
                                             frameSize: CGSize(width: Design.videoWidth * ratio,
                                                               height: Design.videoHeight * ratio),
                                             shouldLoopVideo: false,
                                             cornerRadiusRatio: ratio)
                    }
                }
            }
            .aspectRatio(Design.borderWidth / Design.borderHeight, contentMode: .fit)
        }
    }

}
