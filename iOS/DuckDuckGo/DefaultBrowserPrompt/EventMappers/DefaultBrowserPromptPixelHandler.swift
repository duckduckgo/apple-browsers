//
//  DefaultBrowserPromptPixelHandler.swift
//  DuckDuckGo
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

import Foundation
import Common
import Core
import SetDefaultBrowserCore

final class DefaultBrowserPromptPixelHandler: EventMapping<DefaultBrowserPromptEvent>, DefaultBrowserPromptEventMapping {
    private let pixelFiring: PixelFiring.Type

    public init(pixelFiring: PixelFiring.Type = Pixel.self) {
        self.pixelFiring = pixelFiring

        super.init { event, _, _, _ in
            switch event {
            case let .activeModalShown(numberOfModalShown):
                pixelFiring.fire(.defaultBrowserPromptModalShown, withAdditionalParameters: Self.parameters(forNumberOfModalsShown: numberOfModalShown))
            case .activeModalDismissed:
                pixelFiring.fire(.defaultBrowserPromptModalClosedButtonTapped, withAdditionalParameters: [:])
            case .activeModalDismissedPermanently:
                pixelFiring.fire(.defaultBrowserPromptModalDoNotAskAgainButtonTapped, withAdditionalParameters: [:])
            case let .activeModalActioned(numberOfModalShown):
                pixelFiring.fire(.defaultBrowserPromptModalSetAsDefaultBrowserButtonTapped, withAdditionalParameters: Self.parameters(forNumberOfModalsShown: numberOfModalShown))
            case .inactiveModalShown:
                pixelFiring.fire(.defaultBrowserPromptInactiveUserModalShown, withAdditionalParameters: [:])
            case .inactiveModalDismissed:
                pixelFiring.fire(.defaultBrowserPromptInactiveUserModalClosedButtonTapped, withAdditionalParameters: [:])
            case .inactiveModalActioned:
                pixelFiring.fire(.defaultBrowserPromptInactiveUserModalSetAsDefaultBrowserButtonTapped, withAdditionalParameters: [:])
            case .inactiveModalMoreProtectionsAction:
                pixelFiring.fire(.defaultBrowserPromptInactiveUserModalMoreProtectionsButtonTapped, withAdditionalParameters: [:])
            }
        }
    }

    @available(*, unavailable, message: "Use init() instead")
    override init(mapping: @escaping EventMapping<DefaultBrowserPromptEvent>.Mapping) {
        fatalError("Use init()")
    }

    private static func parameters(forNumberOfModalsShown value: Int) -> [String: String] {
        let value = value > 10 ? "10+" : String(value)
        return [
            PixelParameters.defaultBrowserPromptNumberOfModalsShown: value
        ]
    }

}
