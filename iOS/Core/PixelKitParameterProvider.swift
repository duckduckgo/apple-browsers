//
//  PixelKitParameterProvider.swift
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

import Foundation
import BrowserServicesKit
import PixelKit

/// Supplies PixelKit with the iOS values it cannot derive itself.
///
/// Reads through to the statistics store on each access rather than caching, because there is no ATB
/// until `StatisticsLoader` has completed the app's first ATB request, and it is updated afterwards.
///
/// The default store matches the one the legacy `Pixel` path used through
/// `StatisticsDependentURLFactory`, so a pixel that opts into `atb` gets the same value it would
/// have got before migrating.
public final class IOSPixelKitParameterProvider: PixelKitParameterProviding {

    private let statisticsStore: StatisticsStore

    public init(statisticsStore: StatisticsStore = StatisticsUserDefaults()) {
        self.statisticsStore = statisticsStore
    }

    public var atb: String? {
        statisticsStore.atbWithVariant
    }
}
