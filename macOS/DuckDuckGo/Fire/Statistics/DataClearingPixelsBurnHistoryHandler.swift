//
//  DataClearingPixelsBurnHistoryHandler.swift
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

import History
import Foundation

struct DataClearingPixelsBurnHistoryHandler: DataClearingPixelsHandling {

    private let dataClearingPixelsReporter: DataClearingPixelsReporter

    init(_ dataClearingPixelsReporter: DataClearingPixelsReporter = DataClearingPixelsReporter()) {
        self.dataClearingPixelsReporter = dataClearingPixelsReporter
    }

    func fireErrorPixel(_ error: Error) {
        dataClearingPixelsReporter.fireErrorPixel(DataClearingPixels.burnHistoryError(error))
    }

    func fireDurationPixel(_ startTime: CFTimeInterval) {
        // BurnVisits is one step inside burnHistory
        // Firing burnVisits pixel instead of burnHistory pixel to get a more granular measurement
        dataClearingPixelsReporter.fireDurationPixel(DataClearingPixels.burnVisitsDuration, from: startTime)
    }
}
