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
    enum ProfileSetup {
        case seedIfMissing(DataBrokerProtectionProfile)
        case resetAndSeed(DataBrokerProtectionProfile)
    }

    let profileSetup: ProfileSetup?
    let startServer: Bool

    enum ParseError: LocalizedError {
        case invalidBooleanArgument(name: String)
        case invalidProfile
        case resetRequiresProfile

        var errorDescription: String? {
            switch self {
            case .invalidBooleanArgument(let name): return "Launch argument \(name) must be true or false."
            case .invalidProfile: return "Invalid PIR profile JSON or required profile fields."
            case .resetRequiresProfile: return "PIR reset requires valid profile JSON."
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

        let startServer = try pirDebugBoolean(value(argument: "pirDebugServer", environmentKey: "PIR_DEBUG_SERVER"), argument: "pirDebugServer")
        let reset = try pirDebugBoolean(value(argument: "pirResetBeforeSeeding", environmentKey: "PIR_RESET_BEFORE_SEEDING"), argument: "pirResetBeforeSeeding")
        let profileValue = value(argument: "pirProfileJSON", environmentKey: "PIR_PROFILE_JSON")
        let profileSetup: PIRDebugLaunchOptions.ProfileSetup?
        if let profileValue {
            guard let profile = try? JSONDecoder().decode(DataBrokerProtectionProfile.self, from: Data(profileValue.utf8)),
                  !profile.names.isEmpty, !profile.addresses.isEmpty,
                  profile.names.allSatisfy({ !$0.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  profile.addresses.allSatisfy({ !$0.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  profile.phones.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  (1900...Calendar.current.component(.year, from: Date())).contains(profile.birthYear) else {
                throw ParseError.invalidProfile
            }
            profileSetup = reset ? .resetAndSeed(profile) : .seedIfMissing(profile)
        } else {
            guard !reset else { throw ParseError.resetRequiresProfile }
            profileSetup = nil
        }
        guard profileSetup != nil || startServer else { return nil }
        return PIRDebugLaunchOptions(profileSetup: profileSetup, startServer: startServer)
    }

    private static func pirDebugBoolean(_ value: String?, argument: String) throws -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: throw ParseError.invalidBooleanArgument(name: argument)
        }
    }
}
#endif
