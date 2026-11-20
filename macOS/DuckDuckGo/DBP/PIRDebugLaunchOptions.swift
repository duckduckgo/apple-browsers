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
import DataBrokerProtectionCore
import DDGError
import Foundation

struct PIRDebugLaunchOptions {
    struct ProfileSetup {
        let profile: DataBrokerProtectionProfile
        let resetBeforeSeeding: Bool
    }

    struct ManagedSeed {
        enum Mode: String, Codable {
            case seed
            case reseed
        }

        let mode: Mode
        let instanceID: String
        let receiptURL: URL

        var resetBeforeSeeding: Bool { mode == .reseed }

        func validateAccount(rawAuthenticated: Bool, pirAuthenticated: Bool) throws {
            guard !rawAuthenticated, !pirAuthenticated else { throw ParseError.authenticatedAccount }
        }

        func validateExistingProfile(_ hasProfile: Bool) throws {
            guard mode == .reseed || !hasProfile else { throw ParseError.existingProfile }
        }
    }

    let profileSetup: ProfileSetup?
    let startServer: Bool
    let managedSeed: ManagedSeed?

    enum ParseError: DDGError {
        case invalidProfile
        case resetRequiresProfile
        case invalidManagedRequest
        case invalidReceipt
        case conflictingReset
        case authenticatedAccount
        case existingProfile

        static var errorDomain: String { "com.duckduckgo.pir.debug-launch-options" }

        var errorCode: Int {
            switch self {
            case .invalidProfile: return 0
            case .resetRequiresProfile: return 1
            case .invalidManagedRequest: return 2
            case .invalidReceipt: return 3
            case .conflictingReset: return 4
            case .authenticatedAccount: return 5
            case .existingProfile: return 6
            }
        }

        var description: String {
            switch self {
            case .invalidProfile: return "Invalid PIR profile JSON or required profile fields."
            case .resetRequiresProfile: return "PIR reset requires valid profile JSON."
            case .invalidManagedRequest: return "PIR scheduler mode requires seed or reseed, a UUID, a receipt path, and valid profile JSON."
            case .invalidReceipt: return "PIR scheduler receipt requires an absolute file path in an existing writable directory."
            case .conflictingReset: return "PIR scheduler mode cannot be combined with the legacy reset option."
            case .authenticatedAccount: return "PIR scheduler seeding requires an unauthenticated account."
            case .existingProfile: return "PIR scheduler seed requires an empty profile store; use reseed to replace it."
            }
        }

        var receiptErrorCode: String {
            switch self {
            case .invalidProfile: return "invalidProfile"
            case .resetRequiresProfile: return "resetRequiresProfile"
            case .invalidManagedRequest: return "invalidManagedRequest"
            case .invalidReceipt: return "invalidReceipt"
            case .conflictingReset: return "conflictingReset"
            case .authenticatedAccount: return "authenticatedAccount"
            case .existingProfile: return "profileAlreadyExists"
            }
        }
    }

    static func hasManagedRequest(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        ["PIR_SCHEDULER_MODE", "PIR_SCHEDULER_INSTANCE_ID", "PIR_SCHEDULER_RECEIPT"].contains { environment[$0] != nil }
    }

    /// Also resolves a receipt destination for malformed requests whose identity and destination are valid.
    static func managedSeed(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ManagedSeed? {
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
        return ManagedSeed(mode: mode, instanceID: instanceID, receiptURL: url)
    }

    static func parse(
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
