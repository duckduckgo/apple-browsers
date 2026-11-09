//
//  LocalModelService.swift
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

import AIChat
import AppKit
import Combine
import FeatureFlags_macOS
import PrivacyConfig

/// A Duck.ai page that can receive local-model pushes.
@MainActor
protocol AIChatLocalModelPushing: AnyObject {
    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate)
    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk)
}

/// What the Duck.ai user script needs from the local model.
@MainActor
protocol AIChatLocalModelServing: AnyObject {
    /// The `localModel` config field, or nil when the feature flag is off.
    func config() -> AIChatLocalModelConfig?
    func register(_ pusher: AIChatLocalModelPushing)
    func startRun(_ request: AIChatLocalRunRequest, for pusher: AIChatLocalModelPushing) throws -> AIChatLocalRunStartReply
    func cancelRun(requestId: String)
    func cancelRuns(ownerID: ObjectIdentifier)
    func setUp() throws
}

/// Owns the local-model opt-in state and the runs. App-wide rather than per web view, because only
/// one run may use the model at a time and every Duck.ai page must see the same state.
@MainActor
final class LocalModelService: AIChatLocalModelServing {

    static let supportedTasks = AIChatLocalModelTask.allCases

    @Published private(set) var availability: AIChatLocalModelAvailability

    private let featureFlagger: FeatureFlagger
    private let storage: AIChatPreferencesStorage
    private let engine: AIChatLocalModelEngine
    private let runQueue: AIChatLocalRunQueue
    private let pushers = NSHashTable<AnyObject>.weakObjects()
    private var lastPushedState: AIChatLocalModelState?
    private var cancellables = Set<AnyCancellable>()

    init(featureFlagger: FeatureFlagger,
         storage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
         engine: AIChatLocalModelEngine = AppleFoundationModelEngine(),
         runQueue: AIChatLocalRunQueue? = nil,
         notificationCenter: NotificationCenter = .default) {
        self.featureFlagger = featureFlagger
        self.storage = storage
        self.engine = engine
        self.runQueue = runQueue ?? AIChatLocalRunQueue(engine: engine)
        self.availability = Self.uncheckedAvailability
        self.lastPushedState = currentState

        storage.pageSummariesModelPublisher
            .removeDuplicates()
            .sink { [weak self] _ in self?.pushStateIfChanged() }
            .store(in: &cancellables)

        featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshAvailability() }
            .store(in: &cancellables)

        // Apple Intelligence is turned on and off in System Settings, so check again whenever the user comes back.
        notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshAvailability() }
            .store(in: &cancellables)

        refreshAvailability()
    }

    /// Stands in while the flag is off, so launch doesn't touch Foundation Models for everyone else.
    private static let uncheckedAvailability = AIChatLocalModelAvailability.unsupportedOS

    var isFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatLocalModels)
    }

    var isOptedIn: Bool {
        storage.pageSummariesModel == .appleIntelligence
    }

    var model: AIChatLocalModelInfo {
        engine.model
    }

    /// The state Duck.ai sees, or nil when the feature flag is off.
    var currentState: AIChatLocalModelState? {
        guard isFeatureEnabled else { return nil }
        guard availability.isAvailable else { return .unsupported }
        return isOptedIn ? .ready : .notSetUp
    }

    var availabilityPublisher: AnyPublisher<AIChatLocalModelAvailability, Never> {
        $availability.removeDuplicates().eraseToAnyPublisher()
    }

    /// Fires when the flag, the opt-in or availability may have changed.
    var changesPublisher: AnyPublisher<Void, Never> {
        Publishers.Merge3(
            availabilityPublisher.map { _ in () },
            storage.pageSummariesModelPublisher.map { _ in () },
            featureFlagger.updatesPublisher
        )
        .eraseToAnyPublisher()
    }

    func refreshAvailability() {
        let latest = isFeatureEnabled ? engine.availability : Self.uncheckedAvailability
        if latest != availability {
            availability = latest
        }
        pushStateIfChanged()
    }

    func optIn() {
        setPageSummariesModel(.appleIntelligence)
    }

    func optOut() {
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

    func config() -> AIChatLocalModelConfig? {
        refreshAvailability()
        guard let state = currentState else { return nil }
        return AIChatLocalModelConfig(state: state, tasks: Self.supportedTasks, model: engine.model, downloadBytes: 0)
    }

    func register(_ pusher: AIChatLocalModelPushing) {
        pushers.add(pusher)
    }

    func startRun(_ request: AIChatLocalRunRequest, for pusher: AIChatLocalModelPushing) throws -> AIChatLocalRunStartReply {
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

    func cancelRun(requestId: String) {
        runQueue.cancel(requestId: requestId)
    }

    func cancelRuns(ownerID: ObjectIdentifier) {
        runQueue.cancelAll(ownerID: ownerID)
    }

    func setUp() throws {
        refreshAvailability()
        guard isFeatureEnabled, availability.isAvailable else {
            throw AIChatLocalModelRequestError.unavailable
        }
        optIn()
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
