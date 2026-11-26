//
//  PIRDebugLaunchOptions.swift
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

#if DEBUG
import DDGError
import Foundation

public struct PIRDebugLaunchOptions {
    public struct ProfileSetup {
        public let profile: DataBrokerProtectionProfile
        public let resetBeforeSeeding: Bool
    }

    public struct DebugScanJob: Codable, Equatable {
        public let brokerURL: String
        public let profileQueryId: Int64

        public init(brokerURL: String, profileQueryId: Int64) {
            self.brokerURL = brokerURL
            self.profileQueryId = profileQueryId
        }
    }

    public struct ManagedSeed {
        public enum Mode: String, Codable {
            case seed
            case reseed
        }

        public let mode: Mode
        public let instanceID: String
        public let receiptURL: URL
        /// Brokers the seed and the scheduled scans it starts are limited to; nil scans every eligible broker.
        public let brokerURLs: [String]?

        public init(mode: Mode, instanceID: String, receiptURL: URL, brokerURLs: [String]? = nil) {
            self.mode = mode
            self.instanceID = instanceID
            self.receiptURL = receiptURL
            self.brokerURLs = brokerURLs
        }

        public var resetBeforeSeeding: Bool { mode == .reseed }

        /// Stores the seed's broker subset for the scheduler, or clears an earlier one so every eligible broker runs again.
        public func applyBrokerSelection(to settings: DataBrokerProtectionSettings) {
            settings.debugTestBrokerURLs = brokerURLs
        }

        public func validateAccount(rawAuthenticated: Bool, pirAuthenticated: Bool) throws {
            guard !rawAuthenticated, !pirAuthenticated else { throw ParseError.authenticatedAccount }
        }

        public func validateExistingProfile(_ hasProfile: Bool) throws {
            guard mode == .reseed || !hasProfile else { throw ParseError.existingProfile }
        }

        /// Uses the same active broker, profile query, and Freemium scan selection as the manual scan scheduler.
        public func scanJobs(database: DataBrokerProtectionRepository) throws -> [DebugScanJob] {
            let jobs = try PIRDebugLaunchOptions.scanJobs(database: database, isAuthenticatedUser: false,
                                                          brokerURLs: brokerURLs, includesMaintenance: false)
            if let brokerURLs {
                let planned = Set(jobs.map(\.brokerURL))
                let missing = brokerURLs.filter { !planned.contains($0) }
                if !missing.isEmpty { throw ParseError.unknownBroker(try Self.reasons(for: missing, database: database)) }
            }
            guard !jobs.isEmpty else { throw ParseError.emptyScanPlan }
            return jobs
        }

        /// Why each requested broker has no Freemium scan: `notStored`, `removed`, `requiresSubscription` or `noScanJob`.
        private static func reasons(for brokerURLs: [String], database: DataBrokerProtectionRepository) throws -> [String: String] {
            let stored = try database.fetchAllDataBrokers()
            return Dictionary(uniqueKeysWithValues: brokerURLs.map { url in
                guard let broker = stored.first(where: { $0.url == url }) else { return (url, "notStored") }
                if broker.isRemoved { return (url, "removed") }
                return (url, broker.scanRequiresSubscription ? "requiresSubscription" : "noScanJob")
            })
        }

        private struct Receipt: Encodable {
            let instanceID: String
            let mode: Mode
            let status: String
            let since: Date
            let jobs: [DebugScanJob]
            let errorCode: String?
            let missingBrokers: [String: String]?
        }

        public func writeReceipt(since: Date, jobs: [DebugScanJob] = [], error: Error? = nil) throws {
            let code: String?
            if let error = error as? ParseError {
                code = error.receiptErrorCode
            } else if let error {
                code = "launch_\((error as NSError).code)"
            } else {
                code = nil
            }
            var missingBrokers: [String: String]?
            if case .unknownBroker(let reasons) = error as? ParseError { missingBrokers = reasons }
            let receipt = Receipt(instanceID: instanceID, mode: mode, status: error == nil ? "ready" : "error",
                                  since: since, jobs: jobs, errorCode: code, missingBrokers: missingBrokers)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(receipt).write(to: receiptURL, options: .atomic)
        }
    }

    public let profileSetup: ProfileSetup?
    public let startServer: Bool
    public let managedSeed: ManagedSeed?

    public enum ParseError: DDGError {
        case invalidProfile
        case resetRequiresProfile
        case invalidManagedRequest
        case invalidReceipt
        case conflictingReset
        case authenticatedAccount
        case existingProfile
        case emptyScanPlan
        case unknownBroker([String: String])

        public static var errorDomain: String { "com.duckduckgo.pir.debug-launch-options" }

        public var errorCode: Int {
            switch self {
            case .invalidProfile: return 0
            case .resetRequiresProfile: return 1
            case .invalidManagedRequest: return 2
            case .invalidReceipt: return 3
            case .conflictingReset: return 4
            case .authenticatedAccount: return 5
            case .existingProfile: return 6
            case .emptyScanPlan: return 7
            case .unknownBroker: return 8
            }
        }

        public var description: String {
            switch self {
            case .invalidProfile: return "Invalid PIR profile JSON or required profile fields."
            case .resetRequiresProfile: return "PIR reset requires valid profile JSON."
            case .invalidManagedRequest: return "PIR scheduler mode requires seed or reseed, a UUID, a receipt path, and valid profile JSON."
            case .invalidReceipt: return "PIR scheduler receipt requires an absolute file path in an existing writable directory."
            case .conflictingReset: return "PIR scheduler mode cannot be combined with the legacy reset option."
            case .authenticatedAccount: return "PIR scheduler seeding requires an unauthenticated account."
            case .existingProfile: return "PIR scheduler seed requires an empty profile store; use reseed to replace it."
            case .emptyScanPlan: return "PIR scheduler seeding produced no eligible scan jobs."
            case .unknownBroker: return "A PIR scheduler seed broker has no eligible scan job."
            }
        }

        public var receiptErrorCode: String {
            switch self {
            case .invalidProfile: return "invalidProfile"
            case .resetRequiresProfile: return "resetRequiresProfile"
            case .invalidManagedRequest: return "invalidManagedRequest"
            case .invalidReceipt: return "invalidReceipt"
            case .conflictingReset: return "conflictingReset"
            case .authenticatedAccount: return "authenticatedAccount"
            case .existingProfile: return "profileAlreadyExists"
            case .emptyScanPlan: return "emptyScanPlan"
            case .unknownBroker: return "unknownBroker"
            }
        }
    }

    /// The scans a manual scan run would start for this account, limited to `brokerURLs` when given.
    public static func scanJobs(database: DataBrokerProtectionRepository, isAuthenticatedUser: Bool,
                                brokerURLs: [String]?, includesMaintenance: Bool) throws -> [DebugScanJob] {
        let queries = try database.fetchEligibleBrokerProfileQueryData(isAuthenticatedUser: isAuthenticatedUser)
            .filter { !$0.profileQuery.deprecated }
        return BrokerProfileJob.sortedEligibleJobs(brokerProfileQueriesData: queries, jobType: .manualScan, priorityDate: nil)
            .compactMap { job -> DebugScanJob? in
                guard let scan = job as? ScanJobData, includesMaintenance || scan.scanType() != .maintenance, scan.profileQueryId > 0,
                      let query = queries.first(where: { $0.dataBroker.id == scan.brokerId && $0.profileQuery.id == scan.profileQueryId }) else {
                    return nil
                }
                return DebugScanJob(brokerURL: query.dataBroker.url, profileQueryId: scan.profileQueryId)
            }
            .filter { brokerURLs?.contains($0.brokerURL) ?? true }
    }

    /// Makes these scans due now, so an immediate run doesn't skip them for a later preferred run date.
    public static func makeScansDue(_ jobs: [DebugScanJob], database: DataBrokerProtectionRepository) throws {
        let brokers = try database.fetchAllDataBrokers()
        let now = Date()
        for job in jobs {
            guard let brokerId = brokers.first(where: { $0.url == job.brokerURL })?.id else { continue }
            try database.updatePreferredRunDate(now, brokerId: brokerId, profileQueryId: job.profileQueryId)
        }
    }

    public static func hasManagedRequest(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        ["PIR_SCHEDULER_MODE", "PIR_SCHEDULER_INSTANCE_ID", "PIR_SCHEDULER_RECEIPT"].contains { environment[$0] != nil }
    }

    public static func managedSeed(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ManagedSeed? {
        guard hasManagedRequest(environment: environment) else { return nil }
        guard let modeValue = environment["PIR_SCHEDULER_MODE"], let mode = ManagedSeed.Mode(rawValue: modeValue),
              let instanceID = environment["PIR_SCHEDULER_INSTANCE_ID"], UUID(uuidString: instanceID) != nil else {
            throw ParseError.invalidManagedRequest
        }
        guard let path = environment["PIR_SCHEDULER_RECEIPT"], (path as NSString).isAbsolutePath,
              !path.contains("\0"), !path.hasSuffix("/") else { throw ParseError.invalidReceipt }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard url.standardizedFileURL.path == path,
              manager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue,
              manager.isWritableFile(atPath: parent.path) else { throw ParseError.invalidReceipt }
        if let attributes = try? manager.attributesOfItem(atPath: path) {
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ParseError.invalidReceipt }
        }
        var brokerURLs: [String]?
        if let value = environment["PIR_SCHEDULER_BROKERS"] {
            guard let urls = try? JSONDecoder().decode([String].self, from: Data(value.utf8)), !urls.isEmpty,
                  urls.allSatisfy({ !$0.isEmpty }) else { throw ParseError.invalidManagedRequest }
            brokerURLs = urls
        }
        return ManagedSeed(mode: mode, instanceID: instanceID, receiptURL: url, brokerURLs: brokerURLs)
    }

    public static func parse(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> PIRDebugLaunchOptions? {
        let arguments = arguments.dropFirst()
        func value(argument: String, environmentKey: String) -> String? {
            guard let index = arguments.lastIndex(of: "-\(argument)") else { return environment[environmentKey] }
            let valueIndex = arguments.index(after: index)
            return valueIndex < arguments.endIndex ? arguments[valueIndex] : ""
        }

        let managedSeed = try managedSeed(environment: environment)
        if managedSeed != nil {
            guard environment["PIR_RESET_BEFORE_SEEDING"] == nil, !arguments.contains("-pirResetBeforeSeeding") else {
                throw ParseError.conflictingReset
            }
        }
        let startServer = managedSeed != nil || value(argument: "pirDebugServer", environmentKey: "PIR_DEBUG_SERVER") == "true"
        let reset = value(argument: "pirResetBeforeSeeding", environmentKey: "PIR_RESET_BEFORE_SEEDING") == "true"
        let profileValue = value(argument: "pirProfileJSON", environmentKey: "PIR_PROFILE_JSON")
        let profileSetup: PIRDebugLaunchOptions.ProfileSetup?
        if let profileValue {
            guard let profile = try? JSONDecoder().decode(DataBrokerProtectionProfile.self, from: Data(profileValue.utf8)) else {
                throw ParseError.invalidProfile
            }

            func hasText(_ value: String) -> Bool {
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            let hasValidNames = !profile.names.isEmpty && profile.names.allSatisfy { name in
                hasText(name.firstName) && hasText(name.lastName)
            }
            let hasValidAddresses = !profile.addresses.isEmpty && profile.addresses.allSatisfy { address in
                hasText(address.city) && hasText(address.state)
            }
            let hasValidPhones = profile.phones.allSatisfy(hasText)
            let currentYear = Calendar.current.component(.year, from: Date())
            let hasValidBirthYear = (1900...currentYear).contains(profile.birthYear)

            guard hasValidNames, hasValidAddresses, hasValidPhones, hasValidBirthYear else {
                throw ParseError.invalidProfile
            }
            profileSetup = ProfileSetup(profile: profile, resetBeforeSeeding: reset)
        } else {
            guard managedSeed == nil else { throw ParseError.invalidManagedRequest }
            guard !reset else { throw ParseError.resetRequiresProfile }
            profileSetup = nil
        }
        guard profileSetup != nil || startServer else { return nil }
        return PIRDebugLaunchOptions(profileSetup: profileSetup, startServer: startServer, managedSeed: managedSeed)
    }
}
#endif
