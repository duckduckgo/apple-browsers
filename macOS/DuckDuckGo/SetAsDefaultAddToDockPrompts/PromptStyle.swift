//
//  PromptStyle.swift
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

enum PromptStyle {
    case popover(PromptContent)
    case banner(PromptContent)

    var title: String? {
        switch self {
        case let .popover(content):
            return content.title
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
            switch content {
            case .addToDockPrompt: return .attIconBanner
            default: return .greenShield
            }
        }
    }

    var message: String {
        switch self {
        case let .popover(content):
            switch content {
            case .addToDockPrompt:
                return "Get quick access to protected browsing when you add DuckDuckGo to your Dock."
            case .setAsDefaultPrompt:
                return "Make us your default browser so all site links open in DuckDuckGo"
            case .both:
                return "Make us your default browser so all site links open in DuckDuckGo, and add us to your Dock for quick access."
            }
        case let .banner(content):
            switch content {
            case .addToDockPrompt: return "Get quick access to protected browsing"
            default: return "Protect more of what you do online"
            }
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case let .popover(content):
            switch content {
            case .addToDockPrompt: return "Add To Dock"
            default: return "Set As Default Browser"
            }
        case let .banner(content):
            switch content {
            case .addToDockPrompt: return "Add DuckDuckGo To Dock..."
            default: return "Set DuckDuckGo As Default Browser..."
            }
        }
    }

    var secondaryButtonTitle: String? {
        switch self {
        case .popover:
            return "Not Now"
        default:
            return nil
        }
    }
}

enum PromptContent {
    case both
    case setAsDefaultPrompt
    case addToDockPrompt

    var title: String {
        switch self {
        case .addToDockPrompt:
            return "Add DuckDuckGo to your Dock"
        default:
            return "Let DuckDuckGo protect more of what you do online"
        }
    }

    static func getStyle(isSparkle: Bool, isDefaultBrowser: Bool, isOnDock: Bool) -> PromptContent? {
        if isSparkle {
            if isDefaultBrowser && isOnDock {
                return nil
            } else if isDefaultBrowser && !isOnDock {
                return .addToDockPrompt
            } else if !isDefaultBrowser && isOnDock {
                return .setAsDefaultPrompt
            } else {
                return .both
            }
        } else {
            return isDefaultBrowser ? nil : .setAsDefaultPrompt
        }
    }
}
