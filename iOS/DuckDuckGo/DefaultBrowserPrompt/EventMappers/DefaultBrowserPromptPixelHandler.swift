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
import FoundationExtensions
import Core
import PixelKit
import SetDefaultBrowserCore

final class DefaultBrowserPromptPixelHandler: EventMapping<DefaultBrowserPromptEvent>, DefaultBrowserPromptEventMapping {
    private let pixelFiring: (any PixelKitFiring)?

    public init(pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.pixelFiring = pixelFiring

        super.init { event, _, _, _ in
            switch event {
            case let .activeModalShown(numberOfModalShown):
                pixelFiring?.fire(Pixel.Event.defaultBrowserPromptModalShown, options: .parameters(Self.parameters(forNumberOfModalsShown: numberOfModalShown)))
            case .activeModalDismissed:
                pixelFiring?.fire(Pixel.Event.defaultBrowserPromptModalClosedButtonTapped, options: .parameters([:]))
            case .activeModalDismissedPermanently:
                pixelFiring?.fire(Pixel.Event.defaultBrowserPromptModalDoNotAskAgainButtonTapped, options: .parameters([:]))
            case let .activeModalActioned(numberOfModalShown):
                pixelFiring?.fire(Pixel.Event.defaultBrowserPromptModalSetAsDefaultBrowserButtonTapped, options: .parameters(Self.parameters(forNumberOfModalsShown: numberOfModalShown)))
            case .inactiveModalShown:
                pixelFiring?.fire(Pixel.Event.defaultBrowserPromptInactiveUserModalShown, options: .parameters([:]))
            case .inactiveModalDismissed:
                pixelFiring?.fire(Pixel.Event.defaultBrowserPromptInactiveUserModalClosedButtonTapped, options: .parameters([:]))
            case .inactiveModalActioned:
                pixelFiring?.fire(Pixel.Event.defaultBrowserPromptInactiveUserModalSetAsDefaultBrowserButtonTapped, options: .parameters([:]))
            case .inactiveModalMoreProtectionsAction:
                pixelFiring?.fire(Pixel.Event.defaultBrowserPromptInactiveUserModalMoreProtectionsButtonTapped, options: .parameters([:]))
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
