//
//  UpdatePromptScheduleTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

@Suite("Update prompt schedule")
struct UpdatePromptScheduleTests {

    private let releaseDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let installed = "7.240.0"
    private let os = "18.0"

    private func day(_ days: Double) -> Date {
        releaseDate.addingTimeInterval(days * 24 * 60 * 60)
    }

    private func release(_ version: String = "7.241.0", daysAfterFirst: Double = 0, minimumOS: String = "16.0") -> AppStoreRelease {
        AppStoreRelease(version: version, releaseDate: day(daysAfterFirst), minimumOSVersion: minimumOS)
    }

    /// Runs the schedule like the app does: evaluate, keep the state, and record the step as shown.
    private struct Device {
        var installedVersion: String
        var osVersion = "18.0"
        var state: UpdatePromptState?

        mutating func open(at now: Date, release: AppStoreRelease?) -> UpdatePromptStep? {
            let evaluation = UpdatePromptSchedule.evaluate(installedVersion: installedVersion,
                                                           osVersion: osVersion,
                                                           release: release,
                                                           state: state,
                                                           now: now)
            state = evaluation.state
            if let step = evaluation.step {
                state = state?.recordingShown(step, at: now)
            }
            return evaluation.step
        }
    }

    // MARK: - Nothing to update

    @available(iOS 16, macOS 13, *)
    @Test("No release known shows nothing and clears state", .timeLimit(.minutes(1)))
    func noRelease() {
        var device = Device(installedVersion: installed)
        #expect(device.open(at: day(3), release: release()) == .first)

        #expect(device.open(at: day(30), release: nil) == nil)
        #expect(device.state == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Same or older release shows nothing", .timeLimit(.minutes(1)),
          arguments: ["7.240.0", "7.240", "7.239.9", "6.999.0"])
    func notNewer(version: String) {
        var device = Device(installedVersion: installed)
        #expect(device.open(at: day(30), release: release(version)) == nil)
        #expect(device.state == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Versions compare per component, not as text", .timeLimit(.minutes(1)))
    func numericComparison() {
        var device = Device(installedVersion: "7.99.0")
        #expect(device.open(at: day(3), release: release("7.100.0")) == .first)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unreadable versions show nothing", .timeLimit(.minutes(1)))
    func unreadableVersion() {
        var device = Device(installedVersion: installed)
        #expect(device.open(at: day(30), release: release("7.x")) == nil)
    }

    // MARK: - Schedule

    @available(iOS 16, macOS 13, *)
    @Test("Asks on day 2, 7 and 14, then never again", .timeLimit(.minutes(1)))
    func fullSchedule() {
        var device = Device(installedVersion: installed)
        let release = release()

        #expect(device.open(at: day(1.9), release: release) == nil)
        #expect(device.open(at: day(2), release: release) == .first)
        #expect(device.open(at: day(3), release: release) == nil)
        #expect(device.open(at: day(7), release: release) == .second)
        #expect(device.open(at: day(13), release: release) == nil)
        #expect(device.open(at: day(14), release: release) == .last)
        #expect(device.open(at: day(15), release: release) == nil)
        #expect(device.open(at: day(400), release: release) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("First open on day 20 shows the first reminder, not the last", .timeLimit(.minutes(1)))
    func lateFirstOpen() {
        var device = Device(installedVersion: installed)
        #expect(device.open(at: day(20), release: release()) == .first)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each later reminder waits the full gap after the previous one was shown", .timeLimit(.minutes(1)))
    func waitsFullGap() {
        var device = Device(installedVersion: installed)
        let release = release()

        #expect(device.open(at: day(20), release: release) == .first)
        #expect(device.open(at: day(24.9), release: release) == nil)
        #expect(device.open(at: day(25), release: release) == .second)
        #expect(device.open(at: day(31.9), release: release) == nil)
        #expect(device.open(at: day(32), release: release) == .last)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only one reminder per evaluation", .timeLimit(.minutes(1)))
    func oneStepAtATime() {
        let evaluation = UpdatePromptSchedule.evaluate(installedVersion: installed, osVersion: os,
                                                       release: release(), state: nil, now: day(30))
        #expect(evaluation.step == .first)
        #expect(evaluation.state?.lastShown == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A reminder that wasn't presented stays due", .timeLimit(.minutes(1)))
    func notRecordedUntilShown() {
        let first = UpdatePromptSchedule.evaluate(installedVersion: installed, osVersion: os,
                                                  release: release(), state: nil, now: day(3))
        let again = UpdatePromptSchedule.evaluate(installedVersion: installed, osVersion: os,
                                                  release: release(), state: first.state, now: day(4))
        #expect(again.step == .first)
    }

    // MARK: - Clock

    @available(iOS 16, macOS 13, *)
    @Test("Weekly releases don't restart the clock", .timeLimit(.minutes(1)))
    func weeklyReleasesKeepClock() {
        var device = Device(installedVersion: installed)

        #expect(device.open(at: day(2), release: release("7.241.0")) == .first)
        #expect(device.open(at: day(7), release: release("7.242.0", daysAfterFirst: 7)) == .second)
        #expect(device.open(at: day(14), release: release("7.243.0", daysAfterFirst: 14)) == .last)
        #expect(device.open(at: day(21), release: release("7.244.0", daysAfterFirst: 21)) == nil)
        #expect(device.state?.clockStart == releaseDate)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Updating the app starts over for the new installed version", .timeLimit(.minutes(1)))
    func installedVersionChangeResets() {
        var device = Device(installedVersion: installed)
        let firstRelease = release("7.241.0")
        #expect(device.open(at: day(2), release: firstRelease) == .first)
        #expect(device.open(at: day(7), release: firstRelease) == .second)
        #expect(device.open(at: day(14), release: firstRelease) == .last)

        device.installedVersion = "7.241.0"
        let nextRelease = release("7.245.0", daysAfterFirst: 30)
        #expect(device.open(at: day(31), release: nextRelease) == nil)
        #expect(device.open(at: day(32), release: nextRelease) == .first)
        #expect(device.state?.installedVersion == "7.241.0")
        #expect(device.state?.clockStart == nextRelease.releaseDate)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Catching up to the latest version clears the state", .timeLimit(.minutes(1)))
    func upToDateClears() {
        var device = Device(installedVersion: installed)
        #expect(device.open(at: day(2), release: release()) == .first)

        device.installedVersion = "7.241.0"
        #expect(device.open(at: day(3), release: release()) == nil)
        #expect(device.state == nil)
    }

    // MARK: - OS

    @available(iOS 16, macOS 13, *)
    @Test("Devices that can't run the new version are never asked", .timeLimit(.minutes(1)))
    func osTooOld() {
        var device = Device(installedVersion: installed, osVersion: "15.8")
        let release = release(minimumOS: "16.0")
        for day in [2.0, 7, 14, 30] {
            #expect(device.open(at: self.day(day), release: release) == nil)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("OS versions compare per component", .timeLimit(.minutes(1)))
    func osComparison() {
        var device = Device(installedVersion: installed, osVersion: "16.10")
        #expect(device.open(at: day(2), release: release(minimumOS: "16.9")) == .first)
        var exact = Device(installedVersion: installed, osVersion: "16")
        #expect(exact.open(at: day(2), release: release(minimumOS: "16.0")) == .first)
    }

    // MARK: - Decoding

    @available(iOS 16, macOS 13, *)
    @Test("Decodes the release metadata file", .timeLimit(.minutes(1)))
    func decodesMetadata() throws {
        let json = """
        {"latest_appstore_version": {"latest_version": "7.250.0", "build_number": 123,
         "release_date": "2026-11-23T15:00:45Z", "minimum_os_version": "16.0"}}
        """
        let metadata = try AppStoreReleaseMetadata.decode(from: Data(json.utf8))

        #expect(metadata.latest == AppStoreRelease(version: "7.250.0",
                                                   releaseDate: Date(timeIntervalSince1970: 1_795_446_045),
                                                   minimumOSVersion: "16.0"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Decodes release dates with fractional seconds", .timeLimit(.minutes(1)))
    func decodesFractionalSeconds() throws {
        let json = """
        {"latest_appstore_version": {"latest_version": "7.250.0",
         "release_date": "2026-11-23T15:00:45.500Z", "minimum_os_version": "16.0"}}
        """
        let metadata = try AppStoreReleaseMetadata.decode(from: Data(json.utf8))

        #expect(metadata.latest.releaseDate == Date(timeIntervalSince1970: 1_795_446_045.5))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Rejects metadata without a minimum OS version", .timeLimit(.minutes(1)))
    func rejectsIncompleteMetadata() {
        let json = """
        {"latest_appstore_version": {"latest_version": "7.250.0", "release_date": "2026-11-23T15:00:45Z"}}
        """
        #expect(throws: DecodingError.self) { try AppStoreReleaseMetadata.decode(from: Data(json.utf8)) }
    }
}
