//
//  KeyExpirationTester.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import ConcurrencyExtensions
import Foundation
import FoundationExtensions
import Network
import NetworkExtension
import os.log

/// Rekey timer for the VPN
///
final actor KeyExpirationTester: KeyExpirationTesting {

    private let canRekey: @MainActor () async -> Bool

    /// The interval of time between the start of each TCP connection test.
    ///
    private let intervalBetweenTests: TimeInterval = .seconds(15)

    private let rekeyFailureBackoffIntervals: [TimeInterval] = [
        .seconds(15),
        .seconds(30),
        .seconds(60),
        .seconds(120),
        .seconds(300)
    ]

    /// Provides a simple mechanism to synchronize an `isRunning` flag for the tester to know if it needs to interrupt its operation.
    /// The reason why this is necessary is that the tester may be stopped while the connection tests are already executing, in a bit
    /// of a race condition which could result in the tester returning results when it's already stopped.
    ///
    private(set) var isRunning = false
    private var isTestingExpiration = false
    private var consecutiveFailedRekeyCount = 0
    private var nextRekeyAttemptDate: Date?

    /// Bumped on every `stop()`. A rekey attempt captures this before it suspends so it can tell,
    /// once it resumes, whether a `stop()` interleaved while it was awaiting.
    private var stopGeneration = 0
    private let keyStore: NetworkProtectionKeyStore
    private let rekey: @MainActor () async throws -> Void
    private let settings: VPNSettings
    private var task: Task<Never, Error>?
    private let currentDate: @Sendable () -> Date

    // MARK: - Init & deinit

    init(keyStore: NetworkProtectionKeyStore,
         settings: VPNSettings,
         currentDate: @escaping @Sendable () -> Date = { Date() },
         canRekey: @escaping @MainActor () async -> Bool,
         rekey: @escaping @MainActor () async throws -> Void) {

        self.keyStore = keyStore
        self.rekey = rekey
        self.canRekey = canRekey
        self.settings = settings
        self.currentDate = currentDate

        Logger.networkProtectionMemory.debug("[+] \(String(describing: self), privacy: .public)")
    }

    deinit {
        Logger.networkProtectionMemory.debug("[-] \(String(describing: self), privacy: .public)")
        task?.cancel()
    }

    // MARK: - Starting & Stopping the tester

    func start(testImmediately: Bool) async {
        guard !isRunning else {
            Logger.networkProtectionKeyManagement.log("Will not start the key expiration tester as it's already running")
            return
        }

        isRunning = true

        Logger.networkProtectionKeyManagement.log("🟢 Starting rekey timer")
        await scheduleTimer(testImmediately: testImmediately)
    }

    func stop() {
        Logger.networkProtectionKeyManagement.log("🔴 Stopping rekey timer")
        stopScheduledTimer()
        resetRekeyFailureBackoff()
        stopGeneration &+= 1
        isRunning = false
    }

    // MARK: - Timer scheduling

    private func scheduleTimer(testImmediately: Bool) async {
        stopScheduledTimer()

        if testImmediately {
            await rekeyIfExpired()
        }

        task = Task.periodic(interval: intervalBetweenTests) { [weak self] in
            await self?.rekeyIfExpired()
        }
    }

    private func stopScheduledTimer() {
        task?.cancel()
        task = nil
    }

    // MARK: - Testing the connection

    private var isKeyExpired: Bool {
        guard let currentExpirationDate = keyStore.currentExpirationDate else {
            return true
        }

        return currentExpirationDate <= currentDate()
    }

    // MARK: - Expiration check

    func rekeyIfExpired() async {

        guard !isTestingExpiration else {
            return
        }

        isTestingExpiration = true

        defer {
            isTestingExpiration = false
        }

        // Remember the stop generation before we start awaiting. `rekeyIfExpired()` suspends at the
        // `await`s below, during which `stop()` can run on the actor and clear the failure backoff.
        // If that happens, recording a failure afterwards would restore the very backoff `stop()`
        // just cleared, causing a fresh `start()` to honor a stale delay.
        let stopGenerationAtStart = stopGeneration

        guard await canRekey() else {
            Logger.networkProtectionKeyManagement.log("Can't rekey right now as some preconditions aren't met.")
            return
        }

        Logger.networkProtectionKeyManagement.log("Checking if rekey is necessary...")

        guard isKeyExpired else {
            Logger.networkProtectionKeyManagement.log("The key is not expired")
            resetRekeyFailureBackoff()
            return
        }

        if let nextRekeyAttemptDate, currentDate() < nextRekeyAttemptDate {
            Logger.networkProtectionKeyManagement.log("Rekeying is delayed after a previous failure.")
            return
        }

        Logger.networkProtectionKeyManagement.log("Rekeying now.")
        do {
            try await rekey()
            resetRekeyFailureBackoff()
            Logger.networkProtectionKeyManagement.log("Rekeying completed.")
        } catch {
            guard stopGenerationAtStart == stopGeneration else {
                Logger.networkProtectionKeyManagement.log("Rekey failed after the tester was stopped; not recording a failure backoff.")
                return
            }

            recordRekeyFailure()
            Logger.networkProtectionKeyManagement.error("Rekeying failed with error: \(error, privacy: .public).")
        }
    }

    private func recordRekeyFailure() {
        consecutiveFailedRekeyCount += 1
        let backoffIndex = min(consecutiveFailedRekeyCount - 1, rekeyFailureBackoffIntervals.count - 1)
        nextRekeyAttemptDate = currentDate().addingTimeInterval(rekeyFailureBackoffIntervals[backoffIndex])
    }

    private func resetRekeyFailureBackoff() {
        consecutiveFailedRekeyCount = 0
        nextRekeyAttemptDate = nil
    }

    // MARK: - Key Validity

    func setKeyValidity(_ interval: TimeInterval?) {
        if let interval {
            let firstExpirationDate = Date().addingTimeInterval(interval)
            Logger.networkProtectionKeyManagement.log("Setting key validity interval to \(String(describing: interval), privacy: .public) seconds (next expiration date \(String(describing: firstExpirationDate), privacy: .public))")
            settings.registrationKeyValidity = .custom(interval)
        } else {
            Logger.networkProtectionKeyManagement.log("Resetting key validity interval")
            settings.registrationKeyValidity = .automatic
        }

        keyStore.setValidityInterval(interval)
    }
}
