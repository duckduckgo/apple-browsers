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

import Foundation
import Network
import NetworkExtension
import Common
import os.log

/// Rekey timer for the VPN
///
final actor KeyExpirationTester {

    private let canRekey: @MainActor () async -> Bool

    /// The interval of time between the start of each TCP connection test.
    ///
    private let intervalBetweenTests: TimeInterval = .seconds(15)

    /// Provides a simple mechanism to synchronize an `isRunning` flag for the tester to know if it needs to interrupt its operation.
    /// The reason why this is necessary is that the tester may be stopped while the connection tests are already executing, in a bit
    /// of a race condition which could result in the tester returning results when it's already stopped.
    ///
    private(set) var isRunning = false
    private var isTestingExpiration = false
    private let keyStore: NetworkProtectionKeyStore
    private let rekey: @MainActor () async throws -> Void
    private let settings: VPNSettings
    private var task: Task<Never, Error>?

    // MARK: - Init & deinit

    init(keyStore: NetworkProtectionKeyStore,
         settings: VPNSettings,
         canRekey: @escaping @MainActor () async -> Bool,
         rekey: @escaping @MainActor () async throws -> Void) {

        self.keyStore = keyStore
        self.rekey = rekey
        self.canRekey = canRekey
        self.settings = settings

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

        return currentExpirationDate <= Date()
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

        guard await canRekey() else {
            Logger.networkProtectionKeyManagement.log("Can't rekey right now as some preconditions aren't met.")
            return
        }

        Logger.networkProtectionKeyManagement.log("Checking if rekey is necessary...")

        guard isKeyExpired else {
            Logger.networkProtectionKeyManagement.log("The key is not expired")
            return
        }

        Logger.networkProtectionKeyManagement.log("Rekeying now.")
        do {
            try await rekey()
            Logger.networkProtectionKeyManagement.log("Rekeying completed.")
        } catch {
            Logger.networkProtectionKeyManagement.error("Rekeying failed with error: \(error, privacy: .public).")
        }
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
