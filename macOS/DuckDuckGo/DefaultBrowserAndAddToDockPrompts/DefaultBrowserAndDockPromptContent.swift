//
//  DefaultBrowserAndDockPromptContent.swift
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

enum DefaultBrowserAndDockPromptType {
    case bothDefaultBrowserAndDockPrompt
    case setAsDefaultPrompt
    case addToDockPrompt
}

enum DefaultBrowserAndDockPromptContent {
    case popover(DefaultBrowserAndDockPromptType)
    case banner(DefaultBrowserAndDockPromptType)

    var title: String? {
        switch self {
        case let .popover(content):
            switch content {
            case .addToDockPrompt:
                return UserText.addDuckDuckGoToDockPopoverTitle
            default:
                return UserText.defaultPopoverTitleForSATandATT
            }
        default:
            return nil
        }
    }

    var icon: NSImage {
        switch self {
        case let .popover(content):
            switch content {
            case .addToDockPrompt: return .attIconPopover
            default: return .addAsDefaultPopoverIcon
            }
        case let .banner(content):
            return .daxBannerView
        }
    }

    var message: String {
        switch self {
        case let .popover(content):
            switch content {
            case .addToDockPrompt:
                return UserText.addToDockPopoverPromptMessage
            case .setAsDefaultPrompt, .bothDefaultBrowserAndDockPrompt:
                return UserText.setAsDefaultPopoverPromptMessage
            }
        case let .banner(content):
            switch content {
            case .addToDockPrompt: return UserText.addToDockBannerPromptMessage
            default: return UserText.bothSetAsDefaultBannerAndAddToDockPromptMessage
            }
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case let .popover(content):
            switch content {
            case .addToDockPrompt: return UserText.addToDockPopoverPrimaryAction
            default: return UserText.bothSetAsDefaultPopoverAndAddToDockPromptPrimaryAction
            }
        case let .banner(content):
            switch content {
            case .addToDockPrompt: return UserText.addDuckDuckGoToDock
            default: return UserText.setAsDefaultBrowser
            }
        }
    }

    var secondaryButtonTitle: String? {
        switch self {
        case .popover:
            return UserText.notNow
        default:
            return nil
        }
    }
}
