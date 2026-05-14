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

import Foundation
import Core

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
    private let topOption: OnboardingAddressBarPositionContent.OptionContent
    private let bottomOption: OnboardingAddressBarPositionContent.OptionContent
    private let defaultIndicator: String

    init(
        addressBarPositionManager: AddressBarPositionManaging = AppUserDefaults(),
        topOption: OnboardingAddressBarPositionContent.OptionContent = .init(
            title: UserText.Onboarding.AddressBarPosition.topTitle,
            message: UserText.Onboarding.AddressBarPosition.topMessage
        ),
        bottomOption: OnboardingAddressBarPositionContent.OptionContent = .init(
            title: UserText.Onboarding.AddressBarPosition.bottomTitle,
            message: UserText.Onboarding.AddressBarPosition.bottomMessage
        ),
        defaultIndicator: String = UserText.Onboarding.AddressBarPosition.defaultOption
    ) {
        self.addressBarPositionManager = addressBarPositionManager
        self.topOption = topOption
        self.bottomOption = bottomOption
        self.defaultIndicator = defaultIndicator
        makeDisplayModels()
    }

    func setAddressBar(position: AddressBarPosition) {
        addressBarPositionManager.currentAddressBarPosition = position
        makeDisplayModels()
    }

    private func makeDisplayModels() {
        items = AddressBarPosition.allCases.map { addressBarPosition in
            let info = titleAndMessage(for: addressBarPosition)

            return DisplayModel(
                type: addressBarPosition,
                icon: addressBarPosition.image,
                title: info.title,
                message: info.message,
                isSelected: addressBarPositionManager.currentAddressBarPosition == addressBarPosition
            )
        }
    }

    private func titleAndMessage(for position: AddressBarPosition) -> (title: NSAttributedString, message: String) {
        switch position {
        case .top:
            let firstPart = NSAttributedString(string: topOption.title)
                .withFont(UIFont.daxBodyBold())
                .withTextColor(UIColor.label)
            let secondPart = NSAttributedString(string: defaultIndicator)
                .withFont(UIFont.daxBodyRegular())
                .withTextColor(UIColor.secondaryLabel)

            return (firstPart + " " + secondPart, topOption.message)
        case .bottom:
            return (
                NSAttributedString(string: bottomOption.title)
                    .withFont(UIFont.daxBodyBold()),
                bottomOption.message
            )
        }
    }
}

// MARK: - AddressBarPositionManaging

protocol AddressBarPositionManaging: AnyObject {
    var currentAddressBarPosition: AddressBarPosition { get set }
}

extension AppUserDefaults: AddressBarPositionManaging {}

// MARK: - AddressBarPosition Helpers

private extension AddressBarPosition {

    var image: ImageResource {
        switch self {
        case .top: .addressBarTop
        case .bottom: .addressBarBottom
        }
    }

}
