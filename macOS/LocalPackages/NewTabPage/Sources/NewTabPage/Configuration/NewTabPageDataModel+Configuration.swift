//
//  NewTabPageDataModel+Configuration.swift
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

public extension NewTabPageDataModel {
    struct OpenAction: Codable {
        let target: Target

        public enum Target: String, Codable {
            case settings
            case duckAISettings
        }
    }
}

extension NewTabPageDataModel {

    enum WidgetId: String, Codable {
        case rmf, freemiumPIRBanner, subscriptionWinBackBanner, nextStepsList, omnibar, favorites, protections
    }

    struct ContextMenuParams: Codable {
        let visibilityMenuItems: [ContextMenuItem]

        struct ContextMenuItem: Codable {
            let id: WidgetId
            let title: String
        }
    }

    struct Exception: Codable, Equatable {
        let message: String
    }

    struct NewTabPageConfiguration: Encodable {
        var widgets: [Widget]
        var widgetConfigs: [WidgetConfig]
        var env: String
        var locale: String
        var platform: Platform
        var settings: Settings?
        var customizer: NewTabPageDataModel.CustomizerData?
        var tabs: Tabs?
        var omnibar: Omnibar?

        struct Widget: Encodable, Equatable {
            public var id: WidgetId
        }

        struct WidgetConfig: Codable, Equatable {

            enum WidgetVisibility: String, Codable {
                case visible, hidden

                var isVisible: Bool {
                    self == .visible
                }
            }

            init(id: WidgetId, isVisible: Bool) {
                self.id = id
                self.visibility = isVisible ? .visible : .hidden
            }

            var id: WidgetId
            var visibility: WidgetVisibility
        }

        struct Platform: Encodable, Equatable {
            var name: String
        }

        /// The subset of `omnibar_getConfig` that affects the omnibar's height,
        /// sent up front so the page can reserve the right space while the full config loads.
        struct Omnibar: Encodable, Equatable {
            let mode: OmnibarMode
            let enableAi: Bool
            let showAiSetting: Bool
        }

        struct Settings: Encodable, Equatable {
            let customizerDrawer: Setting
            let newTabPageRebranding: Setting
        }

        struct Setting: Encodable, Equatable {
            let state: BooleanSetting
        }

        enum BooleanSetting: String, Encodable {
            case enabled, disabled

            var isEnabled: Bool {
                self == .enabled
            }
        }
    }
}
