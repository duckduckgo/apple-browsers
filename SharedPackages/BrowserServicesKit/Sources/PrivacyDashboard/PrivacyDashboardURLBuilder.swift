//
//  PrivacyDashboardURLBuilder.swift
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

final class PrivacyDashboardURLBuilder {

    enum Configuration {

        case startScreen(entryPoint: PrivacyDashboardEntryPoint)
        case segueToScreen(_ screen: Screen, entryPoint: PrivacyDashboardEntryPoint)

    }

    private var url: URL
    private let configuration: Configuration

    init(configuration: Configuration) {
        guard let baseURL = Bundle.privacyDashboardURL else { fatalError() }
        self.url = baseURL
        self.configuration = configuration
    }

    func build() -> URL {
        url.addingScreenParameter(from: configuration)
            .addingOpenerParameterIfNeeded(from: configuration)
    }

}

private extension URL {

    private enum Constant {

        static let screenKey = "screen"
        static let openerKey = "opener"
        static let categoryKey = "category"

        static let menuScreenKey = "menu"
        static let dashboardScreenKey = "dashboard"

    }

    func addingScreenParameter(from configuration: PrivacyDashboardURLBuilder.Configuration) -> URL {
        var screen: Screen
        switch configuration {
        case .startScreen(let entryPoint):
            screen = entryPoint.screen
        case .segueToScreen(let destinationScreen, _):
            screen = destinationScreen
        }
        return appendingParameter(name: Constant.screenKey, value: screen.rawValue)
    }

    func addingOpenerParameterIfNeeded(from configuration: PrivacyDashboardURLBuilder.Configuration) -> URL {
        if case .startScreen(let entryPoint) = configuration {
            switch entryPoint {
            case .toggleReport, .report:
                return appendingParameter(name: Constant.openerKey, value: Constant.menuScreenKey)
            default:
                break
            }
        }

        if case .segueToScreen(_, let entryPoint) = configuration, entryPoint == .dashboard {
            return appendingParameter(name: Constant.openerKey, value: Constant.dashboardScreenKey)
        }
        return self
    }

}
