//
//  LaunchProfileTests.swift
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

@Suite("Reading the -launchProfile argument")
struct LaunchProfileArgumentTests {

    @available(iOS 16, macOS 13, *)
    @Test("No argument means no profile", .timeLimit(.minutes(1)))
    func noArgument() throws {
        #expect(try LaunchProfile.load(arguments: ["DuckDuckGo", "-isOnboardingCompleted", "true"]) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Inline JSON is read from the argument value", .timeLimit(.minutes(1)))
    func inlineJSON() throws {
        let profile = try LaunchProfile.load(arguments: ["DuckDuckGo", "-launchProfile", #"{"internalUser": true}"#])
        #expect(profile?.root == ["internalUser": .bool(true)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A path is read as a JSON file", .timeLimit(.minutes(1)))
    func filePath() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try Data(#"{"tabs": ["https://example.com"]}"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let profile = try LaunchProfile.load(arguments: ["-launchProfile", file.path])

        #expect(profile?.root == ["tabs": .array([.string("https://example.com")])])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Booleans and numbers stay distinct", .timeLimit(.minutes(1)))
    func booleansAndNumbers() throws {
        let profile = try LaunchProfile(json: Data(#"{"a": true, "b": 1, "c": 0, "d": 1.5, "e": null}"#.utf8))
        #expect(profile.root == ["a": .bool(true), "b": .number(1), "c": .number(0), "d": .number(1.5), "e": .null])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Problems reading the argument are reported", .timeLimit(.minutes(1)))
    func readProblems() {
        #expect(throws: LaunchProfileError.missingValue) {
            try LaunchProfile.load(arguments: ["DuckDuckGo", "-launchProfile"])
        }
        #expect(throws: LaunchProfileError.notAnObject) {
            try LaunchProfile.load(arguments: ["-launchProfile", "[1, 2]"])
        }
        #expect(throws: LaunchProfileError.unreadableFile("/missing.json")) {
            try LaunchProfile.load(arguments: ["-launchProfile", "/missing.json"])
        }
        #expect {
            try LaunchProfile.load(arguments: ["-launchProfile", "{nope"])
        } throws: { error in
            if case LaunchProfileError.invalidJSON = error { return true }
            return false
        }
    }
}
