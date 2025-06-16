//
//  HistoryViewDataProviderPixelHandler.swift
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

import Combine
import Foundation
import HistoryView
import PixelKit

/**
 * This protocol describes firing range updated pixels from HistoryViewDataProvider.
 */
protocol HistoryViewDataProviderPixelFiring {
    func fireFilterUpdatedPixel(_ query: DataModel.HistoryQueryKind)
}

struct HistoryViewDataProviderPixelHandler: HistoryViewDataProviderPixelFiring {

    /**
     * Due to the nature of filtering by search term (typing the phrase)
     * search term filter pixel uses a debounce.
     */
    func fireFilterUpdatedPixel(_ query: DataModel.HistoryQueryKind) {
        switch query {
        case .rangeFilter(.all), .searchTerm(""):
            firePixel(HistoryViewPixel.filterCleared)
        case .searchTerm:
            searchTermPixelSubject.send()
        default:
            firePixel(HistoryViewPixel.filterSet(.init(query)))
        }
    }

    init(
        firePixel: @escaping (HistoryViewPixel) -> Void = { PixelKit.fire($0, frequency: .dailyAndStandard) },
        debounce: RunLoop.SchedulerTimeType.Stride = .seconds(1)
    ) {
        self.firePixel = firePixel

        searchTermCancellable = searchTermPixelSubject
            .debounce(for: debounce, scheduler: RunLoop.main)
            .sink {
                firePixel(.filterSet(.searchTerm))
            }
    }

    private let firePixel: (HistoryViewPixel) -> Void
    private let searchTermPixelSubject = PassthroughSubject<Void, Never>()
    private let searchTermCancellable: AnyCancellable
}
