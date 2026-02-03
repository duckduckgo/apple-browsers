//
//  OnboardingAddressBarPositionPickerViewModel.swift
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

#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import DesignResourcesKit

extension OnboardingRebranding {

    final class OnboardingAddressBarPositionPickerViewModel: ObservableObject {

        struct DisplayModel {
            let type: AddressBarPosition
            let icon: ImageResource
            let title: NSAttributedString
            let message: String
            let isSelected: Bool
        }

        @Published private(set) var items: [DisplayModel] = []

        private let addressBarPositionManager: AddressBarPositionManaging

        init(addressBarPositionManager: AddressBarPositionManaging) {
            self.addressBarPositionManager = addressBarPositionManager
            makeDisplayModels()
        }

        func setAddressBar(position: AddressBarPosition) {
            addressBarPositionManager.currentAddressBarPosition = position
            makeDisplayModels()
        }

        private func makeDisplayModels() {
            items = AddressBarPosition.allCases.map { addressBarPosition in
                let info = addressBarPosition.titleAndMessage

                return DisplayModel(
                    type: addressBarPosition,
                    icon: addressBarPosition.image,
                    title: info.title,
                    message: info.message,
                    isSelected: addressBarPositionManager.currentAddressBarPosition == addressBarPosition
                )
            }
        }
    }
}

// MARK: - AddressBarPosition Helpers

private extension OnboardingRebranding.AddressBarPosition {

    var titleAndMessage: (title: NSAttributedString, message: String) {
        switch self {
        case .top:
            let firstPart = NSAttributedString(string: OnboardingRebranding.UserText.Onboarding.AddressBarPosition.topTitle)
                .withFont(UIFont.daxBodyBold())
                .withTextColor(UIColor.label)
            let secondPart = NSAttributedString(string: OnboardingRebranding.UserText.Onboarding.AddressBarPosition.defaultOption)
                .withFont(UIFont.daxBodyRegular())
                .withTextColor(UIColor.secondaryLabel)

            return (
                firstPart + " " + secondPart,
                OnboardingRebranding.UserText.Onboarding.AddressBarPosition.topMessage
            )
        case .bottom:
            return (
                NSAttributedString(string: OnboardingRebranding.UserText.Onboarding.AddressBarPosition.bottomTitle)
                    .withFont(UIFont.daxBodyBold()),
                OnboardingRebranding.UserText.Onboarding.AddressBarPosition.bottomMessage
            )
        }
    }

    var image: ImageResource {
        switch self {
        case .top: .addressBarTop
        case .bottom: .addressBarBottom
        }
    }

}
#endif
