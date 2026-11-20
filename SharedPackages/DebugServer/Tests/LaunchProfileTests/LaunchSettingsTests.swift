//
//  LaunchSettingsTests.swift
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
import Testing
@testable import LaunchProfile

@Suite("Applying a launch profile")
struct LaunchSettingsTests {

    /// Stands in for the app's stores: records each write in order.
    private final class Recorder {
        var writes: [String] = []
    }

    private let recorder = Recorder()

    private var settings: LaunchSettings {
        let recorder = recorder
        return LaunchSettings([
            LaunchSetting("resetAppState", summary: "Wipes state.") { (value: Bool) in recorder.writes.append("resetAppState=\(value)") },
            LaunchSetting("internalUser", summary: "Internal user.") { (value: Bool) in recorder.writes.append("internalUser=\(value)") },
            LaunchSetting("featureFlags.sitePermissions", summary: "Flag.", requires: ["internalUser": .bool(true)]) { (value: Bool) in
                recorder.writes.append("sitePermissions=\(value)")
            },
            LaunchSetting("featureFlags.duckPlayer", summary: "Flag.", requires: ["internalUser": .bool(true)]) { (value: Bool) in
                recorder.writes.append("duckPlayer=\(value)")
            },
            LaunchSetting("tabs", summary: "Tabs.") { (value: [String]) in recorder.writes.append("tabs=\(value.joined(separator: ","))") },
        ])
    }

    private func apply(_ json: String) throws -> LaunchProfileOutcome {
        settings.apply(try LaunchProfile(json: Data(json.utf8)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nested objects and dotted keys name the same setting", .timeLimit(.minutes(1)))
    func keysAreJSONPaths() throws {
        let nested = try apply(#"{"internalUser": true, "featureFlags": {"duckPlayer": true}}"#)
        let dotted = try apply(#"{"internalUser": true, "featureFlags.duckPlayer": true}"#)

        #expect(nested == .applied(keys: ["internalUser", "featureFlags.duckPlayer"]))
        #expect(dotted == nested)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Settings apply in catalog order, not JSON order", .timeLimit(.minutes(1)))
    func catalogOrder() throws {
        _ = try apply(#"{"tabs": ["a"], "featureFlags": {"duckPlayer": false, "sitePermissions": true}, "internalUser": true, "resetAppState": true}"#)

        #expect(recorder.writes == ["resetAppState=true", "internalUser=true", "sitePermissions=true", "duckPlayer=false", "tabs=a"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Values are decoded to the setting's type", .timeLimit(.minutes(1)))
    func typedValues() throws {
        _ = try apply(#"{"tabs": ["https://example.com", "https://duck.ai"]}"#)

        #expect(recorder.writes == ["tabs=https://example.com,https://duck.ai"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A profile with any problem writes nothing", .timeLimit(.minutes(1)))
    func allOrNothing() throws {
        let outcome = try apply(#"{"resetAppState": true, "internalUser": "yes"}"#)

        #expect(outcome == .rejected([LaunchProfileProblem(key: "internalUser", message: #""internalUser" expects Bool."#)]))
        #expect(recorder.writes.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A setting's own check runs before anything is written", .timeLimit(.minutes(1)))
    func validation() throws {
        struct NotACohort: Error, CustomStringConvertible { var description: String { "use control or treatment" } }
        let settings = LaunchSettings([
            LaunchSetting("internalUser", summary: "Internal user.") { [recorder] (value: Bool) in recorder.writes.append("internalUser=\(value)") },
            LaunchSetting("experiments.onboarding", summary: "Cohort.", validate: { (cohort: String) in
                guard ["control", "treatment"].contains(cohort) else { throw NotACohort() }
            }, write: { [recorder] (cohort: String) in recorder.writes.append("cohort=\(cohort)") }),
        ])

        let outcome = settings.apply(try LaunchProfile(json: Data(#"{"internalUser": true, "experiments": {"onboarding": "blue"}}"#.utf8)))

        #expect(outcome == .rejected([LaunchProfileProblem(key: "experiments.onboarding",
                                                           message: #""experiments.onboarding" is invalid: use control or treatment"#)]))
        #expect(recorder.writes.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown keys are named by their full path", .timeLimit(.minutes(1)))
    func unknownKeys() throws {
        let outcome = try apply(#"{"featureFlag": {"duckPlayer": true}, "internalUsr": true, "somethingElse": 1, "tab": {}}"#)

        #expect(outcome == .rejected([
            LaunchProfileProblem(key: "featureFlag.duckPlayer", message: #"Unknown key "featureFlag.duckPlayer"."#),
            LaunchProfileProblem(key: "internalUsr", message: #"Unknown key "internalUsr"."#),
            LaunchProfileProblem(key: "somethingElse", message: #"Unknown key "somethingElse"."#),
            LaunchProfileProblem(key: "tab", message: #"Unknown key "tab"."#),
        ]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An object under a group names each member", .timeLimit(.minutes(1)))
    func unknownMemberOfKnownGroup() throws {
        let outcome = try apply(#"{"internalUser": true, "featureFlags": {"nope": true}}"#)

        #expect(outcome == .rejected([LaunchProfileProblem(key: "featureFlags.nope", message: #"Unknown key "featureFlags.nope"."#)]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A setting's requirement must be met by the same profile", .timeLimit(.minutes(1)))
    func requirements() throws {
        let missing = try apply(#"{"featureFlags": {"duckPlayer": true}}"#)
        let wrongValue = try apply(#"{"internalUser": false, "featureFlags": {"duckPlayer": true}}"#)

        let problem = LaunchProfileProblem(key: "featureFlags.duckPlayer",
                                           message: #""featureFlags.duckPlayer" needs "internalUser": true in the same profile."#)
        #expect(missing == .rejected([problem]))
        #expect(wrongValue == .rejected([problem]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("The same key set twice is a problem", .timeLimit(.minutes(1)))
    func duplicateKey() throws {
        let outcome = try apply(#"{"internalUser": true, "featureFlags.duckPlayer": true, "featureFlags": {"duckPlayer": false}}"#)

        #expect(outcome == .rejected([LaunchProfileProblem(key: "featureFlags.duckPlayer", message: #""featureFlags.duckPlayer" is set twice."#)]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed write is reported and later settings still apply", .timeLimit(.minutes(1)))
    func failedWrite() throws {
        struct DiskFull: Error, CustomStringConvertible { var description: String { "disk full" } }
        let settings = LaunchSettings([
            LaunchSetting("tabs", summary: "Tabs.") { (_: [String]) in throw DiskFull() },
            LaunchSetting("internalUser", summary: "Internal user.") { [recorder] (value: Bool) in recorder.writes.append("internalUser=\(value)") },
        ])

        let outcome = settings.apply(try LaunchProfile(json: Data(#"{"tabs": [], "internalUser": true}"#.utf8)))

        #expect(outcome == .partiallyApplied(keys: ["internalUser"], problems: [LaunchProfileProblem(key: "tabs", message: #""tabs" failed: disk full"#)]))
        #expect(recorder.writes == ["internalUser=true"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The outcome is one log line tools can wait for", .timeLimit(.minutes(1)))
    func logLine() {
        #expect(LaunchProfileOutcome.applied(keys: ["internalUser", "tabs"]).logLine == "LAUNCH_PROFILE_APPLIED keys=internalUser,tabs")
        #expect(LaunchProfileOutcome.rejected([
            LaunchProfileProblem(key: "a", message: "First."),
            LaunchProfileProblem(key: "b", message: "Second."),
        ]).logLine == "LAUNCH_PROFILE_FAILED First. Second.")
        #expect(LaunchProfileOutcome.partiallyApplied(keys: ["a"], problems: [LaunchProfileProblem(key: "b", message: "Second.")]).logLine
                == "LAUNCH_PROFILE_FAILED applied=a Second.")
    }
}

@Suite("Choosing one of a setting's options")
struct LaunchSettingChoiceTests {

    private enum Theme: String, CaseIterable {
        case light, dark
    }

    @available(iOS 16, macOS 13, *)
    @Test("A known name writes its option; an unknown one lists the options", .timeLimit(.minutes(1)))
    func choice() throws {
        var chosen: [Theme] = []
        let settings = LaunchSettings([
            .choice("theme", summary: "Theme.", options: Theme.allCases, name: \.rawValue) { chosen.append($0) }
        ])

        let unknown = settings.apply(try LaunchProfile(json: Data(#"{"theme": "blue"}"#.utf8)))
        let known = settings.apply(try LaunchProfile(json: Data(#"{"theme": "dark"}"#.utf8)))

        #expect(unknown == .rejected([LaunchProfileProblem(key: "theme", message: #""theme" is invalid: use one of light, dark."#)]))
        #expect(known.isSuccess)
        #expect(chosen == [.dark])
    }
}
