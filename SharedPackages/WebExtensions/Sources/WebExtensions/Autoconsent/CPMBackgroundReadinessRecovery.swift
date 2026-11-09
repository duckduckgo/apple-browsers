//
//  CPMBackgroundReadinessRecovery.swift
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
import WebKit
import os.log

public enum CPMRecoveryFix: String, CaseIterable, Sendable {
    case installReadiness = "install_readiness"
    case upgradeReadiness = "upgrade_readiness"
    case backgroundWake = "background_wake"
    case backgroundLoadRetry = "background_load_retry"
}

public enum CPMRecoveryOutcome: String, Sendable {
    /// A slow public WebKit background callback completed successfully; not proof of a page response.
    case backgroundReady = "background_ready"
}

/// Counts first-startup response failures: a document committed during a known, unfinished background
/// startup whose dashboard response never arrives, although that startup then succeeds. Detection only,
/// nothing is repaired. Navigation changes, errors and context replacement invalidate tracked documents.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadinessRecovery {
    private struct Startup {
        let identifier: UUID
        let beganAt: Date
        let isFirstLoad: Bool
        var isReady = false
    }

    private struct Document {
        let startup: UUID
        var failed = false
        var didReportMissingResponse = false
    }

    private let pixelFiring: WebExtensionPixelFiring
    private let now: () -> Date
    private var startups: [UUID: Startup] = [:]
    private var activeStartup: UUID?
    private var documents: [String: Document] = [:]

    init(pixelFiring: WebExtensionPixelFiring,
         now: @escaping () -> Date = Date.init) {
        self.pixelFiring = pixelFiring
        self.now = now
    }

    func backgroundStarted(_ identifier: UUID, isFirstLoad: Bool = false) {
        startups = startups.filter { now().timeIntervalSince($0.value.beganAt) < 30 }
        activeStartup = identifier
        startups[identifier] = Startup(identifier: identifier, beganAt: now(), isFirstLoad: isFirstLoad)
    }

    func backgroundCompleted(_ identifier: UUID, succeeded: Bool) {
        guard startups[identifier] != nil else { return }
        if activeStartup == identifier { activeStartup = nil }
        guard succeeded else {
            startups[identifier] = nil
            documents = documents.filter { $0.value.startup != identifier }
            return
        }
        startups[identifier]?.isReady = true
        for tab in Array(documents.keys) {
            reportStartupResponseMissingIfNeeded(in: tab)
        }
    }

    func navigationStarted(in tab: String) {
        documents[tab] = nil
    }

    func navigationCommitted(in tab: String, url: URL) {
        guard let identifier = activeStartup, let startup = startups[identifier], !startup.isReady,
              now().timeIntervalSince(startup.beganAt) < 30,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        documents[tab] = Document(startup: startup.identifier)
        Logger.webExtensions.debug("[CPM Recovery] Tracking document during pending background startup")
    }

    func initializationFailed(in tab: String) {
        documents[tab]?.failed = true
        reportStartupResponseMissingIfNeeded(in: tab)
    }

    func responseReceived(in tab: String) {
        documents[tab] = nil
    }

    func navigationCancelled(in tab: String) {
        documents[tab] = nil
    }

    func invalidate() {
        startups.removeAll()
        activeStartup = nil
        documents.removeAll()
    }

    private func reportStartupResponseMissingIfNeeded(in tab: String) {
        guard let document = documents[tab], document.failed, !document.didReportMissingResponse,
              let startup = startups[document.startup], startup.isFirstLoad, startup.isReady,
              now().timeIntervalSince(startup.beganAt) < 30 else { return }
        documents[tab]?.didReportMissingResponse = true
        pixelFiring.fire(.cpmStartupResponseMissing)
    }
}
