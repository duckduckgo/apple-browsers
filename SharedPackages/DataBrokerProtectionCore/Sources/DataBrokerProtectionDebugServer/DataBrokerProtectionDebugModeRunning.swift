//
//  DataBrokerProtectionDebugModeRunning.swift
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

import DataBrokerProtectionCore
import DDGError
import Foundation

/// Calls return without waiting for the work, so callers poll `run(id:)`. Nothing is saved to the PIR database.
public protocol DataBrokerProtectionDebugModeRunning: AnyObject {
    func startScan(_ request: DebugModeScanRequest) throws -> DebugModeRun
    func run(id: String) -> DebugModeRun?
    func startOptOut(runId: String, resultId: String) throws -> DebugModeRun
    func checkForEmailConfirmation(runId: String) throws -> DebugModeRun
    func continueOptOut(runId: String, resultId: String) throws -> DebugModeRun
}

public enum DebugModeRunError: DDGError {
    case invalidRequest(String)
    case brokerNotFound(String)
    case runNotFound(String)
    case resultNotFound(String)
    case busy(runId: String)
    case notAwaitingEmailConfirmation(resultId: String)

    public static var errorDomain: String { "com.duckduckgo.pir.debug-mode-run" }

    public var errorCode: Int {
        switch self {
        case .invalidRequest: return 0
        case .brokerNotFound: return 1
        case .runNotFound: return 2
        case .resultNotFound: return 3
        case .busy: return 4
        case .notAwaitingEmailConfirmation: return 5
        }
    }

    public var description: String {
        switch self {
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .brokerNotFound(let identifier):
            return "Broker not found: \(identifier)"
        case .runNotFound(let id):
            return "Run not found: \(id)"
        case .resultNotFound(let id):
            return "Result not found: \(id)"
        case .busy(let runId):
            return "Run \(runId) is still busy; wait for its activity to finish"
        case .notAwaitingEmailConfirmation(let id):
            return "Result \(id) has no email confirmation link yet; check for email confirmation first"
        }
    }
}

public struct DebugModeScanRequest {
    public enum Broker: Equatable {
        /// A stored broker's url or name.
        case stored(String)
        case json(Data)
    }

    public let broker: Broker
    public let profile: DataBrokerProtectionProfile
    public let hidesWebView: Bool

    public init(broker: Broker, profile: DataBrokerProtectionProfile, hidesWebView: Bool) {
        self.broker = broker
        self.profile = profile
        self.hidesWebView = hidesWebView
    }

    public init(body: Data?) throws {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw DebugModeRunError.invalidRequest("body must be a JSON object")
        }

        switch object["broker"] {
        case let identifier as String where !identifier.isEmpty:
            broker = .stored(identifier)
        case let json as [String: Any]:
            broker = .json(try JSONSerialization.data(withJSONObject: json))
        default:
            throw DebugModeRunError.invalidRequest("'broker' must be a stored broker's url or name, or broker JSON")
        }

        guard let profileObject = object["profile"] as? [String: Any],
              let profileData = try? JSONSerialization.data(withJSONObject: profileObject),
              let profile = try? JSONDecoder().decode(DataBrokerProtectionProfile.self, from: profileData) else {
            throw DebugModeRunError.invalidRequest("'profile' must be a PIR profile with names, addresses, phones and birthYear")
        }
        func hasText(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !profile.names.isEmpty, profile.names.allSatisfy({ hasText($0.firstName) && hasText($0.lastName) }) else {
            throw DebugModeRunError.invalidRequest("'profile' needs at least one name, each with a first and last name")
        }
        guard !profile.addresses.isEmpty, profile.addresses.allSatisfy({ hasText($0.city) && hasText($0.state) }) else {
            throw DebugModeRunError.invalidRequest("'profile' needs at least one address, each with a city and state")
        }
        let currentYear = Calendar.current.component(.year, from: Date())
        guard (1900...currentYear).contains(profile.birthYear) else {
            throw DebugModeRunError.invalidRequest("'profile' birthYear must be between 1900 and \(currentYear)")
        }
        self.profile = profile

        hidesWebView = object["hidesWebView"] as? Bool ?? true
    }
}

public enum DebugModeRunAction: Equatable {
    case optOut(runId: String, resultId: String)
    case continueOptOut(runId: String, resultId: String)
    case checkForEmailConfirmation(runId: String)

    /// `path` is what follows `/api/debug/runs/`.
    public init?(path: String) {
        let components = path.split(separator: "/").map(String.init)
        switch components.count {
        case 3 where components[1] == "optouts":
            self = .optOut(runId: components[0], resultId: components[2])
        case 4 where components[1] == "optouts" && components[3] == "continue":
            self = .continueOptOut(runId: components[0], resultId: components[2])
        case 3 where components[1] == "email-confirmation" && components[2] == "check":
            self = .checkForEmailConfirmation(runId: components[0])
        default:
            return nil
        }
    }
}

public struct DebugModeRun: Encodable {
    public enum Activity: String, Encodable {
        case scan
        case optOut
        case emailConfirmationCheck
        case continueOptOut
    }

    public enum OptOutStatus: String, Encodable {
        case running
        case awaitingEmailConfirmation
        case confirmed
        case failed
    }

    public struct Broker: Encodable {
        public let name: String
        public let url: String

        public init(name: String, url: String) {
            self.name = name
            self.url = url
        }
    }

    public struct Result: Encodable {
        public let id: String
        public let profileQuery: String
        public let name: String?
        public let age: String?
        public let addresses: [String]
        public let profileUrl: String?
        public let optOutStatus: OptOutStatus?
        public let optOutError: String?
        public let hasEmailConfirmationLink: Bool

        public init(id: String,
                    profileQuery: String,
                    name: String?,
                    age: String?,
                    addresses: [String],
                    profileUrl: String?,
                    optOutStatus: OptOutStatus?,
                    optOutError: String?,
                    hasEmailConfirmationLink: Bool) {
            self.id = id
            self.profileQuery = profileQuery
            self.name = name
            self.age = age
            self.addresses = addresses
            self.profileUrl = profileUrl
            self.optOutStatus = optOutStatus
            self.optOutError = optOutError
            self.hasEmailConfirmationLink = hasEmailConfirmationLink
        }
    }

    public struct Event: Encodable {
        public let timestamp: Date
        public let kind: String
        public let profileQuery: String
        public let summary: String
        public let details: String

        public init(timestamp: Date, kind: String, profileQuery: String, summary: String, details: String) {
            self.timestamp = timestamp
            self.kind = kind
            self.profileQuery = profileQuery
            self.summary = summary
            self.details = details
        }
    }

    public let id: String
    public let createdAt: Date
    public let broker: Broker
    public let profileQueries: [String]
    /// Omitted from the JSON once the last activity has finished.
    public let activity: Activity?
    public let scanErrors: [String]
    public let results: [Result]
    public let events: [Event]

    public init(id: String,
                createdAt: Date,
                broker: Broker,
                profileQueries: [String],
                activity: Activity?,
                scanErrors: [String],
                results: [Result],
                events: [Event]) {
        self.id = id
        self.createdAt = createdAt
        self.broker = broker
        self.profileQueries = profileQueries
        self.activity = activity
        self.scanErrors = scanErrors
        self.results = results
        self.events = events
    }
}
