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

/// In-agent data the read service needs. The background agent already holds all of this in process,
/// so the read endpoints read it directly — no XPC. Platform-agnostic; a macOS or iOS agent conforms.
public protocol DataBrokerProtectionDebugReadProviding {
    var agentVersion: String { get }
    var schedulerStateString: String { get }
    var lastSchedulerTrigger: Date? { get }

    func isAuthenticated() async -> Bool
    func hasAccessToken() async -> Bool
    func hasValidEntitlement() async -> Bool

    var environmentName: String { get }
    var endpointURL: URL { get }

    var mainConfigETag: String? { get }
    var lastBrokerJSONUpdateCheck: Date { get }

    func brokerProfileQueryData() throws -> [BrokerProfileQueryData]
    func allBrokerResources() throws -> [BrokerResource]
}

/// Produces read-only, JSON-serializable snapshots of PIR/DBP state for the debug HTTP server.
///
/// Read-only by design: no method mutates state. Three views — a one-shot `snapshot()`, a per-broker
/// `brokerDetail()`, and an `events()` change stream for monitoring progress.
public struct DataBrokerProtectionDebugReadService {

    /// Cap on the events stream when no `since` is supplied, to bound the first-call payload.
    private static let maxEvents = 500

    private let provider: DataBrokerProtectionDebugReadProviding

    public init(provider: DataBrokerProtectionDebugReadProviding) {
        self.provider = provider
    }

    // MARK: - /api

    public func apiIndex() -> DebugAPIIndex {
        DebugAPIIndex(endpoints: [
            .init(path: "/api/snapshot",
                  description: "Current PIR state: agent & scheduler status, auth, per-broker summaries (counts, last scan), and profile queries."),
            .init(path: "/api/brokers/{broker}",
                  description: "Per-broker detail: scan & opt-out state with full history, extracted records, and the broker JSON definition. {broker} = broker url or name."),
            .init(path: "/api/events?since={iso8601}",
                  description: "History events across all brokers, oldest-first. Pass 'since' (ISO-8601) to tail new events; omit for the most recent.")
        ])
    }

    // MARK: - /api/snapshot

    public func snapshot() async throws -> DebugSnapshot {
        let queryData = try provider.brokerProfileQueryData()

        let isAuthenticated = await provider.isAuthenticated()
        let hasAccessToken = await provider.hasAccessToken()
        let hasValidEntitlement = await provider.hasValidEntitlement()
        let auth = DebugSnapshot.Auth(isAuthenticated: isAuthenticated,
                                      hasAccessToken: hasAccessToken,
                                      hasValidEntitlement: hasValidEntitlement,
                                      environment: provider.environmentName,
                                      endpointURL: provider.endpointURL.absoluteString)

        let lastCheck = provider.lastBrokerJSONUpdateCheck
        let brokerUpdate = DebugSnapshot.BrokerUpdate(mainConfigETag: provider.mainConfigETag,
                                                      lastSuccessfulCheck: lastCheck.timeIntervalSince1970 > 0 ? lastCheck : nil)

        return DebugSnapshot(agentVersion: provider.agentVersion,
                             schedulerState: provider.schedulerStateString,
                             lastSchedulerTrigger: provider.lastSchedulerTrigger,
                             auth: auth,
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
                        extractedRecord: extractedRecord(optOut.extractedProfile))
                })
        }

        return DebugBrokerDetail(id: broker.id,
                                 name: broker.name,
                                 url: broker.url,
                                 version: broker.version,
                                 parent: broker.parent,
                                 isRemoved: broker.removedAt != nil,
                                 definition: try brokerDefinition(brokerIdentifier: brokerIdentifier),
                                 profileQueries: queries)
    }

    // MARK: - /api/events

    public func events(since: Date?) throws -> [DebugBrokerEvent] {
        let queryData = try provider.brokerProfileQueryData()
        var events: [DebugBrokerEvent] = []

        for data in queryData {
            let broker = data.dataBroker.url
            for job in data.jobsData {
                let extractedProfileId = (job as? OptOutJobData)?.extractedProfile.id
                for event in job.historyEvents {
                    if let since, event.date <= since { continue }
                    let dto = historyEvent(event)
                    events.append(DebugBrokerEvent(broker: broker,
                                             profileQueryId: event.profileQueryId,
                                             extractedProfileId: extractedProfileId,
                                             type: dto.type,
                                             date: dto.date,
                                             matchCount: dto.matchCount,
                                             error: dto.error))
                }
            }
        }

        let sorted = events.sorted { $0.date < $1.date }
        return since == nil ? Array(sorted.suffix(Self.maxEvents)) : sorted
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

    private func profileQueries(from queryData: [BrokerProfileQueryData]) -> [DebugSnapshot.ProfileQuery] {
        var seenIDs = Set<Int64>()
        var result: [DebugSnapshot.ProfileQuery] = []
        for data in queryData {
            let query = data.profileQuery
            if let id = query.id {
                guard seenIDs.insert(id).inserted else { continue }
            }
            result.append(DebugSnapshot.ProfileQuery(id: query.id,
                                                     firstName: query.firstName,
                                                     lastName: query.lastName,
                                                     middleName: query.middleName,
                                                     suffix: query.suffix,
                                                     city: query.city,
                                                     state: query.state,
                                                     street: query.street,
                                                     zip: query.zip,
                                                     birthYear: query.birthYear,
                                                     age: query.age,
                                                     phone: query.phone,
                                                     deprecated: query.deprecated))
        }
        return result
    }

    private func brokerDefinition(brokerIdentifier: String) throws -> String? {
        let resources = try provider.allBrokerResources()
        guard let resource = resources.first(where: { matches(broker: $0.broker, identifier: brokerIdentifier) }) else {
            return nil
        }
        return DebugHelper.prettyJSONString(from: resource.rawJSON) ?? String(data: resource.rawJSON, encoding: .utf8)
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
            let dto = DebugError(name: error.name, code: error.errorCode, description: error.errorDescription ?? error.name)
            return DebugHistoryEvent(type: eventTypeName(event.type), date: event.date, matchCount: nil, error: dto)
        default:
            return DebugHistoryEvent(type: eventTypeName(event.type), date: event.date, matchCount: nil, error: nil)
        }
    }

    private func extractedRecord(_ profile: ExtractedProfile) -> DebugExtractedRecord {
        DebugExtractedRecord(id: profile.id,
                             name: profile.name,
                             alternativeNames: profile.alternativeNames,
                             addressFull: profile.addressFull,
                             addresses: profile.addresses?.map { $0.fullAddress },
                             phoneNumbers: profile.phoneNumbers,
                             relatives: profile.relatives,
                             profileUrl: profile.profileUrl,
                             reportId: profile.reportId,
                             age: profile.age,
                             email: profile.email,
                             removedDate: profile.removedDate)
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
