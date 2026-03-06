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

        var body: some View {
            ZStack(alignment: .top) {
                OnboardingRebrandingImages.AddToDock.promoBorder
                    .resizable()
                    .padding(.horizontal, -6)
                    .padding(.vertical, -7)
                    .frame(width: 321.0, height: 118.0)
                if let videoURL = Self.videoURL {
                    AddToDockVideoPlayer(
                        url: videoURL,
                        frameSize: CGSize(width: 300.0, height: 120.0)
                    )
                }
            }
        }
    }

}
