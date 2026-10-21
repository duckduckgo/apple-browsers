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
import Foundation

struct PIRDebugLaunchOptions {
    struct ProfileSetup {
        let profile: DataBrokerProtectionProfile
        let resetBeforeSeeding: Bool
    }

    let profileSetup: ProfileSetup?
    let startServer: Bool
    /// Saves the current scan results for the demo brokers to this file.
    let demoCaptureURL: URL?
    /// Seeds saved scan results instead of scanning, so the demo starts at "these sites need you".
    let demoSeed: PIRDemoFixture?

    enum ParseError: LocalizedError {
        case invalidProfile
        case resetRequiresProfile
        case invalidDemoSeed

        var errorDescription: String? {
            switch self {
            case .invalidProfile: return "Invalid PIR profile JSON or required profile fields."
            case .resetRequiresProfile: return "PIR reset requires valid profile JSON."
            case .invalidDemoSeed: return "PIR demo seed file is missing or invalid."
            }
        }
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

        let startServer = value(argument: "pirDebugServer", environmentKey: "PIR_DEBUG_SERVER") == "true"
        let reset = value(argument: "pirResetBeforeSeeding", environmentKey: "PIR_RESET_BEFORE_SEEDING") == "true"
        let profileValue = value(argument: "pirProfileJSON", environmentKey: "PIR_PROFILE_JSON")
        let demoCaptureURL = value(argument: "pirDemoCapture", environmentKey: "PIR_DEMO_CAPTURE").map { URL(fileURLWithPath: $0) }
        let demoSeed = try value(argument: "pirDemoSeed", environmentKey: "PIR_DEMO_SEED").map { path in
            guard let data = FileManager.default.contents(atPath: path),
                  let fixture = try? JSONDecoder().decode(PIRDemoFixture.self, from: data) else { throw ParseError.invalidDemoSeed }
            return fixture
        }
        let profileSetup: PIRDebugLaunchOptions.ProfileSetup?
        if let demoSeed {
            profileSetup = ProfileSetup(profile: demoSeed.profile, resetBeforeSeeding: true)
        } else if let profileValue {
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
            guard !reset else { throw ParseError.resetRequiresProfile }
            profileSetup = nil
        }
        guard profileSetup != nil || startServer || demoCaptureURL != nil else { return nil }
        return PIRDebugLaunchOptions(profileSetup: profileSetup, startServer: startServer,
                                     demoCaptureURL: demoCaptureURL, demoSeed: demoSeed)
    }
}
#endif
