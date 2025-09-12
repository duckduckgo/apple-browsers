//
//  StalledOperationCalculator.swift
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

struct StalledOperationCalculator {
    let isStartEvent: (HistoryEvent) -> Bool
    let isCompletionEvent: (HistoryEvent) -> Bool
    let extractEvents: (BrokerProfileQueryData) -> [[HistoryEvent]]
    let dateRange: Range<Date>

    func calculate(
        from profileQueryData: [BrokerProfileQueryData]
    ) -> (total: Int, stalled: Int, totalByBroker: [String: Int], stalledByBroker: [String: Int]) {
        var totalOperations = 0
        var stalledOperations = 0
        var totalOperationsByBroker: [String: Int] = [:]
        var stalledOperationsByBroker: [String: Int] = [:]

        for data in profileQueryData {
            let eventGroups = extractEvents(data)

            for historyEvents in eventGroups {
                let (startCount, stalledCount) = checkForStalledOperations(in: historyEvents, range: dateRange)

                totalOperations += startCount
                totalOperationsByBroker[data.key] = (totalOperationsByBroker[data.key] ?? 0) + startCount

                stalledOperations += stalledCount
                stalledOperationsByBroker[data.key] = (stalledOperationsByBroker[data.key] ?? 0) + stalledCount
            }
        }

        return (
            total: totalOperations,
            stalled: stalledOperations,
            totalByBroker: totalOperationsByBroker.filter { $0.value > 0 },
            stalledByBroker: stalledOperationsByBroker.filter { $0.value > 0 }
        )
    }

    private func checkForStalledOperations(in historyEvents: [HistoryEvent], range: Range<Date>) -> (startCount: Int, stalledCount: Int) {
        let recentEvents = historyEvents.filter { range.contains($0.date) }
        let sortedEvents = recentEvents.sorted(by: { $0.date < $1.date })

        let startEvents = sortedEvents.filter(isStartEvent)
        var stalledCount = 0

        for (index, startEvent) in startEvents.enumerated() {
            let startDate = startEvent.date
            let endDate = (index + 1 < startEvents.count) ? startEvents[index + 1].date : Date.distantFuture

            let hasCompletion = sortedEvents.contains { event in
                event.date > startDate && event.date < endDate && isCompletionEvent(event)
            }

            if !hasCompletion {
                stalledCount += 1
            }
        }

        return (startCount: startEvents.count, stalledCount: stalledCount)
    }
}

extension StalledOperationCalculator {
    static let scan = StalledOperationCalculator(
        isStartEvent: { event in
            if case .scanStarted = event.type {
                return true
            }
            return false
        },
        isCompletionEvent: { event in
            switch event.type {
            case .noMatchFound, .matchesFound, .reAppearence, .error:
                return true
            default:
                return false
            }
        },
        extractEvents: { [$0.scanJobData.historyEvents] },
        dateRange: Date.daysAgo(7)..<Date().addingTimeInterval(-BrokerJobExecutionConfig().scanJobTimeout)
    )

    static let optOut = StalledOperationCalculator(
        isStartEvent: { event in
            if case .optOutStarted = event.type {
                return true
            }
            return false
        },
        isCompletionEvent: { event in
            switch event.type {
            case .optOutRequested, .optOutSubmittedAndAwaitingEmailConfirmation, .optOutConfirmed, .matchRemovedByUser, .error:
                return true
            default:
                return false
            }
        },
        extractEvents: { $0.optOutJobData.map { $0.historyEvents } },
        dateRange: Date.daysAgo(7)..<Date().addingTimeInterval(-BrokerJobExecutionConfig().optOutJobTimeout)
    )
}

fileprivate extension BrokerProfileQueryData {
    var key: String {
        "\(dataBroker.name)-\(dataBroker.version)"
    }
}
