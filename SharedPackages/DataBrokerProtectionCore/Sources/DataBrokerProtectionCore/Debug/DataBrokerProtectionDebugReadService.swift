//
//  DataBrokerProtectionDebugReadService.swift
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

public protocol DataBrokerProtectionDebugReadProviding {
    var iOSRuntimeStatus: DBPDebugIOSRuntimeStatus? { get }

    var agentVersion: String { get }
    var schedulerStateString: String { get }
    var lastSchedulerTrigger: Date? { get }

    var environmentName: String { get }
    var endpointURL: URL { get }

    var mainConfigETag: String? { get }
    var lastBrokerJSONUpdateCheck: Date { get }

    func brokerProfileQueryData() throws -> [BrokerProfileQueryData]
}

public extension DataBrokerProtectionDebugReadProviding {
    var iOSRuntimeStatus: DBPDebugIOSRuntimeStatus? { nil }
}

public struct DataBrokerProtectionDebugReadService {

    public static let defaultLimit = 500
    public static let maximumLimit = 5_000

    private let provider: DataBrokerProtectionDebugReadProviding

    public init(provider: DataBrokerProtectionDebugReadProviding) {
        self.provider = provider
    }

    // MARK: - /api

    public func apiResponse(endpoints: [DebugAPIResponse.Endpoint]) throws -> DebugAPIResponse {
        DebugAPIResponse(snapshot: try snapshot(), endpoints: endpoints)
    }

    public func defaultEndpoints() -> [DebugAPIResponse.Endpoint] {
        var endpoints: [DebugAPIResponse.Endpoint] = [
            .init(path: "/api/brokers/{broker}",
                  description: "Per-broker detail: scan & opt-out state with full history and extracted records. {broker} = broker url or name."),
            .init(path: "/api/events?since={iso8601}&limit={n}",
                  description: "History events across all brokers, oldest-first. 'since' tails new events; 'limit' defaults to \(Self.defaultLimit) and is capped at \(Self.maximumLimit).")
        ]

        if provider.iOSRuntimeStatus != nil {
            endpoints.insert(.init(path: "/api/runtime-status",
                                   description: "iOS PIR profile state and Secure Vault readiness snapshot."), at: 0)
        }

        return endpoints
    }

    public static func clampedLimit(_ limit: Int?) -> Int {
        guard let limit, limit > 0 else {
            return defaultLimit
        }

        return min(limit, maximumLimit)
    }

    public func runtimeStatus() -> DBPDebugIOSRuntimeStatus? {
        provider.iOSRuntimeStatus
    }

    public func snapshot() throws -> DebugSnapshot {
        let queryData = try provider.brokerProfileQueryData()

        let lastCheck = provider.lastBrokerJSONUpdateCheck
        let brokerUpdate = DebugSnapshot.BrokerUpdate(mainConfigETag: provider.mainConfigETag,
                                                      lastSuccessfulCheck: lastCheck.timeIntervalSince1970 > 0 ? lastCheck : nil)

        return DebugSnapshot(agentVersion: provider.agentVersion,
                             schedulerState: provider.schedulerStateString,
                             lastSchedulerTrigger: provider.lastSchedulerTrigger,
                             environment: provider.environmentName,
                             endpointURL: provider.endpointURL.absoluteString,
                             brokerUpdate: brokerUpdate,
                             brokers: brokerSummaries(from: queryData),
                             profileQueries: profileQueries(from: queryData))
    }

    // MARK: - /api/brokers/{broker}

    public func brokerDetail(brokerIdentifier: String) throws -> DebugBrokerDetail? {
        let group = try provider.brokerProfileQueryData().filter { matches(broker: $0.dataBroker, identifier: brokerIdentifier) }
        guard let broker = group.first?.dataBroker else { return nil }

        let queries = group.map { data in
            DebugBrokerDetail.ProfileQueryDetail(
                profileQueryId: data.scanJobData.profileQueryId,
                scan: DebugBrokerDetail.ScanState(
                    preferredRunDate: data.scanJobData.preferredRunDate,
                    lastRunDate: data.scanJobData.lastRunDate,
                    history: data.scanJobData.historyEvents.sorted { $0.date < $1.date }.map { historyEvent($0) }),
                optOuts: data.optOutJobData.map { optOut in
                    DebugBrokerDetail.OptOutState(
                        extractedProfileId: optOut.extractedProfile.id,
                        attemptCount: optOut.attemptCount,
                        createdDate: optOut.createdDate,
                        preferredRunDate: optOut.preferredRunDate,
                        lastRunDate: optOut.lastRunDate,
                        submittedSuccessfullyDate: optOut.submittedSuccessfullyDate,
                        removedDate: optOut.extractedProfile.removedDate,
                        history: optOut.historyEventsSortedEarliestFirst.map { historyEvent($0) },
                        extractedRecord: debugExtractedRecord(optOut.extractedProfile))
                })
        }

        return DebugBrokerDetail(id: broker.id,
                                 name: broker.name,
                                 url: broker.url,
                                 version: broker.version,
                                 parent: broker.parent,
                                 isRemoved: broker.removedAt != nil,
                                 profileQueries: queries)
    }

    // MARK: - /api/events

    public func events(since: Date?, limit: Int = Self.defaultLimit) throws -> [DebugBrokerEvent] {
        let queryData = try provider.brokerProfileQueryData()
        var events: [DebugBrokerEvent] = []

        for data in queryData {
            let broker = data.dataBroker.url
            for job in data.jobsData {
                let extractedProfileId = (job as? OptOutJobData)?.extractedProfile.id
                for event in job.historyEvents {
                    if let since, event.date <= since { continue }
                    let debugEvent = historyEvent(event)
                    events.append(DebugBrokerEvent(broker: broker,
                                             profileQueryId: event.profileQueryId,
                                             extractedProfileId: extractedProfileId,
                                             type: debugEvent.type,
                                             date: debugEvent.date,
                                             matchCount: debugEvent.matchCount,
                                             error: debugEvent.error))
                }
            }
        }

        let sorted = events.sorted { $0.date < $1.date }
        return Array(sorted.suffix(Self.clampedLimit(limit)))
    }

    // MARK: - Mapping helpers

    private func brokerSummaries(from queryData: [BrokerProfileQueryData]) -> [DebugSnapshot.BrokerSummary] {
        Dictionary(grouping: queryData, by: { $0.dataBroker.url }).values.compactMap { group in
            guard let broker = group.first?.dataBroker else { return nil }
            return DebugSnapshot.BrokerSummary(
                id: broker.id,
                name: broker.name,
                url: broker.url,
                version: broker.version,
                parent: broker.parent,
                isRemoved: broker.removedAt != nil,
                profileQueryCount: group.count,
                matchCount: group.reduce(0) { $0 + $1.optOutJobData.count },
                errorCount: group.reduce(0) { $0 + $1.events.filter { $0.isError }.count },
                lastScanDate: group.compactMap { $0.scanJobData.lastRunDate }.max())
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func profileQueries(from queryData: [BrokerProfileQueryData]) -> [DebugProfileQuery] {
        var seenIDs = Set<Int64>()
        var result: [DebugProfileQuery] = []
        for data in queryData {
            let query = data.profileQuery
            if let id = query.id {
                guard seenIDs.insert(id).inserted else { continue }
            }
            result.append(
                DebugProfileQuery(id: query.id,
                                  deprecated: query.deprecated,
                                  addressCount: query.addresses.count)
            )
        }
        return result
    }

    private func debugExtractedRecord(_ profile: ExtractedProfile) -> DebugExtractedRecord {
        DebugExtractedRecord(id: profile.id,
                             reportId: profile.reportId,
                             removedDate: profile.removedDate,
                             hasName: profile.name?.isEmpty == false,
                             alternativeNameCount: profile.alternativeNames?.count ?? 0,
                             addressCount: profile.addresses?.count ?? 0,
                             phoneCount: profile.phoneNumbers?.count ?? 0,
                             relativeCount: profile.relatives?.count ?? 0,
                             hasAge: profile.age?.isEmpty == false,
                             hasEmail: profile.email?.isEmpty == false,
                             hasProfileURL: profile.profileUrl?.isEmpty == false)
    }

    private func matches(broker: DataBroker, identifier: String) -> Bool {
        broker.url.caseInsensitiveCompare(identifier) == .orderedSame
            || broker.name.caseInsensitiveCompare(identifier) == .orderedSame
    }

    private func historyEvent(_ event: HistoryEvent) -> DebugHistoryEvent {
        switch event.type {
        case .matchesFound(let count):
            return DebugHistoryEvent(type: eventTypeName(event.type), date: event.date, matchCount: count, error: nil)
        case .error(let error):
            let debugError = DebugError(name: error.name, code: error.errorCode, description: error.errorDescription ?? error.name)
            return DebugHistoryEvent(type: eventTypeName(event.type), date: event.date, matchCount: nil, error: debugError)
        default:
            return DebugHistoryEvent(type: eventTypeName(event.type), date: event.date, matchCount: nil, error: nil)
        }
    }

    private func eventTypeName(_ type: HistoryEvent.EventType) -> String {
        switch type {
        case .noMatchFound: return "noMatchFound"
        case .matchesFound: return "matchesFound"
        case .error: return "error"
        case .optOutStarted: return "optOutStarted"
        case .optOutRequested: return "optOutRequested"
        case .optOutSubmittedAndAwaitingEmailConfirmation: return "optOutSubmittedAndAwaitingEmailConfirmation"
        case .optOutConfirmed: return "optOutConfirmed"
        case .scanStarted: return "scanStarted"
        case .reAppearence: return "reAppearence"
        case .matchRemovedByUser: return "matchRemovedByUser"
        }
    }
}
