//
//  ResourceLoadTracker.swift
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

import Combine
import Foundation

/// Tracks resource load state to detect stalled resources — those that sent a request
/// but never received a response within a timeout period.
///
/// A resource is considered "stalled" when it has been waiting for a response longer than
/// `stalledTimeout`. This distinguishes truly stalled connections (e.g. DNS sinkholes)
/// from slow-but-progressing downloads that have received headers and are transferring data.
final class ResourceLoadTracker {

    static let stalledTimeout: TimeInterval = 10

    // MARK: - Resource State

    private enum ResourceState {
        case requestSent(Date)
        case responseReceived
    }

    /// Unique identifier for a resource load, extracted from `_WKResourceLoadInfo.resourceLoadID`.
    typealias ResourceLoadID = UInt64

    private var resources = [ResourceLoadID: ResourceState]()
    private var stalledCheckTimer: Timer?
    private let allResourcesStalledSubject = PassthroughSubject<Void, Never>()

    var allResourcesStalledPublisher: AnyPublisher<Void, Never> {
        allResourcesStalledSubject.eraseToAnyPublisher()
    }

    /// True when there are pending resources and all of them are stalled (no response received).
    var hasOnlyStalledResources: Bool {
        let pendingResources = resources.filter { _, state in
            if case .requestSent = state { return true }
            return false
        }
        guard !pendingResources.isEmpty else { return false }

        let now = Date()
        return pendingResources.allSatisfy { _, state in
            if case .requestSent(let sentDate) = state {
                return now.timeIntervalSince(sentDate) >= Self.stalledTimeout
            }
            return false
        }
    }

    // MARK: - Resource Load ID extraction

    /// Extracts the unique `resourceLoadID` from a `_WKResourceLoadInfo` object.
    static func resourceLoadID(from resourceLoadInfo: Any) -> ResourceLoadID? {
        (resourceLoadInfo as? NSObject)?.value(forKey: "resourceLoadID") as? ResourceLoadID
    }

    // MARK: - Tracking

    func didSendRequest(for id: ResourceLoadID) {
        resources[id] = .requestSent(Date())
        scheduleStalledCheckIfNeeded()
    }

    func didReceiveResponse(for id: ResourceLoadID) {
        resources[id] = .responseReceived
    }

    func didComplete(for id: ResourceLoadID) {
        resources.removeValue(forKey: id)
    }

    func reset() {
        resources.removeAll()
        stalledCheckTimer?.invalidate()
        stalledCheckTimer = nil
    }

    // MARK: - Stalled Detection

    private func scheduleStalledCheckIfNeeded() {
        guard stalledCheckTimer == nil else { return }

        stalledCheckTimer = Timer.scheduledTimer(
            withTimeInterval: Self.stalledTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.checkForStalledResources()
        }
    }

    private func checkForStalledResources() {
        stalledCheckTimer = nil

        if hasOnlyStalledResources {
            allResourcesStalledSubject.send()
        } else {
            // Some resources are still progressing or new ones arrived — check again later
            let hasPendingRequests = resources.contains { _, state in
                if case .requestSent = state { return true }
                return false
            }
            if hasPendingRequests {
                scheduleStalledCheckIfNeeded()
            }
        }
    }
}
