//
//  AIChatLocalModelService.swift
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

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Combine
import Foundation

/// A Duck.ai page that can receive local-model pushes.
@MainActor
public protocol AIChatLocalModelPushing: AnyObject {
    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate)
    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk)
}

/// What the Duck.ai user script needs from the local model.
@MainActor
public protocol AIChatLocalModelServing: AnyObject {
    var model: AIChatLocalModelInfo { get }
    /// The `localModel` config field, or nil when the feature flag is off.
    func config() -> AIChatLocalModelConfig?
    func register(_ pusher: AIChatLocalModelPushing)
    func startRun(_ request: AIChatLocalRunRequest, for pusher: AIChatLocalModelPushing) throws -> AIChatLocalRunStartReply
    func cancelRun(requestId: String, for pusher: AIChatLocalModelPushing)
    func cancelRuns(ownerID: ObjectIdentifier)
    func requestAccess(ask: @MainActor () async -> AIChatLocalModelAccessReply.Result) async throws -> AIChatLocalModelAccessReply.Result
}

/// Owns the local-model opt-in state and the runs. App-wide rather than per web view, because only
/// one run may use the model at a time and every Duck.ai page must see the same state.
@MainActor
public final class AIChatLocalModelService: AIChatLocalModelServing {

    public static let supportedTasks = AIChatLocalModelTask.allCases

    @Published public private(set) var availability: AIChatLocalModelAvailability

    private let isFeatureFlagOn: () -> Bool
    private let featureFlagUpdates: AnyPublisher<Void, Never>
    private let storage: AIChatPageSummariesModelStoring
    private let engine: AIChatLocalModelEngine
    private let runQueue: AIChatLocalRunQueue
    private let pushers = NSHashTable<AnyObject>.weakObjects()
    private var lastPushedState: AIChatLocalModelState?
    private var cancellables = Set<AnyCancellable>()

    public init(isFeatureFlagOn: @escaping () -> Bool,
                featureFlagUpdates: AnyPublisher<Void, Never>,
                storage: AIChatPageSummariesModelStoring,
                engine: AIChatLocalModelEngine = AppleFoundationModelEngine(),
                runQueue: AIChatLocalRunQueue? = nil,
                notificationCenter: NotificationCenter = .default) {
        self.isFeatureFlagOn = isFeatureFlagOn
        self.featureFlagUpdates = featureFlagUpdates
        self.storage = storage
        self.engine = engine
        self.runQueue = runQueue ?? AIChatLocalRunQueue(engine: engine)
        self.availability = Self.uncheckedAvailability
        self.lastPushedState = currentState

        storage.pageSummariesModelPublisher
            .removeDuplicates()
            .sink { [weak self] _ in self?.pushStateIfChanged() }
            .store(in: &cancellables)

        featureFlagUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshAvailability() }
            .store(in: &cancellables)

        // Apple Intelligence is turned on and off in System Settings, so check again whenever the user comes back.
        notificationCenter.publisher(for: Self.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshAvailability() }
            .store(in: &cancellables)

        refreshAvailability()
    }

    /// Stands in while the flag is off, so launch doesn't touch Foundation Models for everyone else.
    private static let uncheckedAvailability = AIChatLocalModelAvailability.unsupportedOS

    private static var didBecomeActiveNotification: Notification.Name {
#if os(macOS)
        NSApplication.didBecomeActiveNotification
#else
        UIApplication.didBecomeActiveNotification
#endif
    }

    public var isFeatureEnabled: Bool {
        isFeatureFlagOn()
    }

    public var isOptedIn: Bool {
        storage.pageSummariesModel == .appleIntelligence
    }

    public var model: AIChatLocalModelInfo {
        engine.model
    }

    /// The state Duck.ai sees, or nil when the feature flag is off.
    public var currentState: AIChatLocalModelState? {
        guard isFeatureEnabled else { return nil }
        guard availability.isAvailable else { return .unsupported }
        return isOptedIn ? .ready : .notSetUp
    }

    public var availabilityPublisher: AnyPublisher<AIChatLocalModelAvailability, Never> {
        $availability.removeDuplicates().eraseToAnyPublisher()
    }

    /// Fires when the flag, the opt-in or availability may have changed.
    public var changesPublisher: AnyPublisher<Void, Never> {
        Publishers.Merge3(
            availabilityPublisher.map { _ in () },
            storage.pageSummariesModelPublisher.map { _ in () },
            featureFlagUpdates
        )
        .eraseToAnyPublisher()
    }

    public func refreshAvailability() {
        let latest = isFeatureEnabled ? engine.availability : Self.uncheckedAvailability
        if latest != availability {
            availability = latest
        }
        pushStateIfChanged()
    }

    public func optIn() {
        setPageSummariesModel(.appleIntelligence)
    }

    public func optOut() {
        setPageSummariesModel(.duckAI)
    }

    private func setPageSummariesModel(_ model: AIChatPageSummariesModel) {
        // The storage publisher fires during the write and the push reads `storage` again. Writing
        // through the stored property would overlap the two accesses and trap; the copy writes to
        // the same store.
        var storage = storage
        storage.pageSummariesModel = model
    }

    // MARK: - AIChatLocalModelServing

    public func config() -> AIChatLocalModelConfig? {
        refreshAvailability()
        guard let state = currentState else { return nil }
        return AIChatLocalModelConfig(state: state, tasks: Self.supportedTasks, model: engine.model)
    }

    public func register(_ pusher: AIChatLocalModelPushing) {
        pushers.add(pusher)
    }

    public func startRun(_ request: AIChatLocalRunRequest, for pusher: AIChatLocalModelPushing) throws -> AIChatLocalRunStartReply {
        refreshAvailability()
        guard currentState == .ready else {
            throw AIChatLocalModelRequestError.unavailable
        }
        guard !request.requestId.isEmpty, !request.content.isEmpty else {
            throw AIChatLocalModelRequestError.invalidArguments
        }
        runQueue.enqueue(request, ownerID: ObjectIdentifier(pusher)) { [weak pusher] chunk in
            pusher?.pushLocalRunChunk(chunk)
        }
        return AIChatLocalRunStartReply(model: engine.model)
    }

    public func cancelRun(requestId: String, for pusher: AIChatLocalModelPushing) {
        runQueue.cancel(requestId: requestId, ownerID: ObjectIdentifier(pusher))
    }

    public func cancelRuns(ownerID: ObjectIdentifier) {
        runQueue.cancelAll(ownerID: ownerID)
    }

    /// `ask` shows the platform's prompt. It isn't called when the user already turned the model on.
    public func requestAccess(ask: @MainActor () async -> AIChatLocalModelAccessReply.Result) async throws -> AIChatLocalModelAccessReply.Result {
        refreshAvailability()
        guard isFeatureEnabled, availability.isAvailable else {
            throw AIChatLocalModelRequestError.unavailable
        }
        if isOptedIn { return .allowed }

        let result = await ask()
        if result == .allowed {
            optIn()
        }
        return result
    }

    // MARK: - Pushes

    private func pushStateIfChanged() {
        let state = currentState
        guard state != lastPushedState else { return }
        lastPushedState = state
        // With the flag off Duck.ai treats the model as unsupported, so tell open pages exactly that.
        let update = AIChatLocalModelStateUpdate(state: state ?? .unsupported)
        for case let pusher as AIChatLocalModelPushing in pushers.allObjects {
            pusher.pushLocalModelState(update)
        }
    }
}
