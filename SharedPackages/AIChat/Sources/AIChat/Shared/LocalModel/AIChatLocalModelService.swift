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

/// A Duck.ai page's script that can receive local-model pushes.
@MainActor
public protocol AIChatLocalModelPushing: AnyObject {
    /// The page the script serves, such as its web view. A page's scripts are replaced while it
    /// stays open, for example when content blocking rules change, so a run belongs to the page and
    /// its output goes to whichever script serves it now. Nil makes the script its own page.
    var localModelPage: AnyObject? { get }
    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate)
    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk)
}

public extension AIChatLocalModelPushing {
    var localModelPage: AnyObject? { nil }

    /// Identifies the page's runs, for `cancelRuns(ownerID:)`.
    var localModelPageID: ObjectIdentifier {
        ObjectIdentifier(localModelPage ?? self)
    }
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
    func requestAccess(ask: @MainActor (AIChatLocalModelAccessRequest) async -> AIChatLocalModelAccessReply.Result) async throws -> AIChatLocalModelAccessReply.Result
}

/// What the access prompt asks the user for.
public enum AIChatLocalModelAccessRequest: Equatable, Sendable {
    /// A model that's already on the device, like Apple Intelligence.
    case connect(AIChatLocalModelInfo)
    /// A model that has to be downloaded first.
    case install(AIChatLocalModelInfo, bytes: Int64)
}

/// The engines that can run local summaries.
public enum AIChatLocalModelEngineKind: String, CaseIterable, Sendable {
    case appleIntelligence
    case llama
}

/// A llama.cpp engine can free its model before the file is deleted.
public protocol AIChatLocalModelUnloading: AnyObject {
    func unloadModel()
}

extension AIChatLlamaEngine: AIChatLocalModelUnloading {}

/// The third-party model: its engine and the downloader that puts its file on disk.
public struct AIChatDownloadableLocalModel {
    public let engine: AIChatLocalModelEngine & AIChatLocalModelUnloading
    public let installer: AIChatLocalModelInstalling

    public init(engine: AIChatLocalModelEngine & AIChatLocalModelUnloading, installer: AIChatLocalModelInstalling) {
        self.engine = engine
        self.installer = installer
    }
}

/// Owns the local-model opt-in state and the runs. App-wide rather than per web view, because only
/// one run may use the model at a time and every Duck.ai page must see the same state.
///
/// Two engines can run summaries: Apple Intelligence, and a downloadable model on llama.cpp for
/// devices without it. Once the downloadable model is installed it stays in use until it's
/// uninstalled, even if Apple Intelligence becomes available later.
@MainActor
public final class AIChatLocalModelService: AIChatLocalModelServing {

    public static let supportedTasks = AIChatLocalModelTask.allCases

    /// Apple Intelligence's availability.
    @Published public private(set) var availability: AIChatLocalModelAvailability
    /// Whether llama.cpp can run here.
    @Published public private(set) var downloadableModelAvailability: AIChatLocalModelAvailability

    private let isFeatureFlagOn: () -> Bool
    private let featureFlagUpdates: AnyPublisher<Void, Never>
    private let storage: AIChatPageSummariesModelStoring
    private let engine: AIChatLocalModelEngine
    private let downloadableModel: AIChatDownloadableLocalModel?
    private let engineOverride: () -> AIChatLocalModelEngineKind?
    private let engineOverrideUpdates: AnyPublisher<Void, Never>
    private let runQueue: AIChatLocalRunQueue
    private let instrumentation: AIChatLocalModelInstrumentation?
    /// In the order they registered, so the newest script for a page is the last one.
    private var pushers: [WeakPusher] = []
    private var lastPushed: PushedState?
    private var cancellables = Set<AnyCancellable>()

    private struct PushedState: Equatable {
        let update: AIChatLocalModelStateUpdate?
        let engine: AIChatLocalModelEngineKind
    }

    /// - Parameters:
    ///   - engine: Apple Intelligence.
    ///   - downloadableModel: The model for devices without Apple Intelligence, or nil to offer none.
    ///   - engineOverride: Forces an engine, from the debug menu. Nil picks one as described above.
    public init(isFeatureFlagOn: @escaping () -> Bool,
                featureFlagUpdates: AnyPublisher<Void, Never>,
                storage: AIChatPageSummariesModelStoring,
                engine: AIChatLocalModelEngine = AppleFoundationModelEngine(),
                downloadableModel: AIChatDownloadableLocalModel? = nil,
                engineOverride: @escaping () -> AIChatLocalModelEngineKind? = { nil },
                engineOverrideUpdates: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher(),
                runQueue: AIChatLocalRunQueue? = nil,
                notificationCenter: NotificationCenter = .default,
                instrumentation: AIChatLocalModelInstrumentation? = nil) {
        self.isFeatureFlagOn = isFeatureFlagOn
        self.featureFlagUpdates = featureFlagUpdates
        self.storage = storage
        self.engine = engine
        self.downloadableModel = downloadableModel
        self.engineOverride = engineOverride
        self.engineOverrideUpdates = engineOverrideUpdates
        let routingEngine = RoutingEngine()
        self.runQueue = runQueue ?? AIChatLocalRunQueue(engine: routingEngine)
        self.instrumentation = instrumentation
        self.availability = Self.uncheckedAvailability
        self.downloadableModelAvailability = Self.uncheckedAvailability
        self.lastPushed = pushedState
        routingEngine.activeEngine = { [weak self] in self?.activeEngine }

        storage.pageSummariesModelPublisher
            .removeDuplicates()
            .sink { [weak self] _ in self?.pushStateIfChanged() }
            .store(in: &cancellables)

        downloadableModel?.installer.statePublisher
            .sink { [weak self] _ in self?.pushStateIfChanged() }
            .store(in: &cancellables)

        Publishers.Merge(featureFlagUpdates, engineOverrideUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshAvailabilityAndReportState() }
            .store(in: &cancellables)

        // Apple Intelligence is turned on and off in System Settings, so check again whenever the user comes back.
        notificationCenter.publisher(for: Self.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshAvailabilityAndReportState() }
            .store(in: &cancellables)

        refreshAvailabilityAndReportState()
    }

    /// Stands in while the flag is off, so launch doesn't touch Foundation Models or llama.cpp for everyone else.
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

    /// The engine Duck.ai gets.
    public var activeEngineKind: AIChatLocalModelEngineKind {
        guard let downloadableModel else { return .appleIntelligence }
        if let forced = engineOverride() {
            return forced
        }
        let installState = downloadableModel.installer.state
        if installState.isInstalled || installState.isDownloading {
            return .llama
        }
        // While Apple's own model downloads, Duck.ai is told it's unsupported rather than offered
        // a second download.
        if availability.isAvailable || availability == .modelNotReady {
            return .appleIntelligence
        }
        return downloadableModelAvailability.isAvailable ? .llama : .appleIntelligence
    }

    private var activeEngine: AIChatLocalModelEngine {
        switch activeEngineKind {
        case .appleIntelligence: return engine
        case .llama: return downloadableModel?.engine ?? engine
        }
    }

    /// The downloadable model's installer, for Settings.
    public var installer: AIChatLocalModelInstalling? {
        downloadableModel?.installer
    }

    /// The active engine is on: Apple Intelligence is turned on, or the downloadable model is installed.
    public var isOptedIn: Bool {
        switch activeEngineKind {
        case .appleIntelligence: return storage.pageSummariesModel == .appleIntelligence
        case .llama: return downloadableModel?.installer.state.isInstalled ?? false
        }
    }

    public var model: AIChatLocalModelInfo {
        activeEngine.model
    }

    /// The state Duck.ai sees, or nil when the feature flag is off.
    public var currentState: AIChatLocalModelState? {
        guard isFeatureEnabled else { return nil }
        switch activeEngineKind {
        case .appleIntelligence:
            guard availability.isAvailable else { return .unsupported }
            return storage.pageSummariesModel == .appleIntelligence ? .ready : .notSetUp
        case .llama:
            guard let downloadableModel, downloadableModelAvailability.isAvailable else { return .unsupported }
            switch downloadableModel.installer.state {
            case .installed: return .ready
            case .downloading: return .downloading
            case .notInstalled, .failed: return .notSetUp
            }
        }
    }

    /// Why setting up the downloadable model failed, while Duck.ai sees `not_set_up` because of it.
    public var setupError: AIChatLocalModelSetupError? {
        guard currentState == .notSetUp, activeEngineKind == .llama,
              case .failed(let error) = downloadableModel?.installer.state else { return nil }
        return error
    }

    public var availabilityPublisher: AnyPublisher<AIChatLocalModelAvailability, Never> {
        $availability.removeDuplicates().eraseToAnyPublisher()
    }

    /// Fires when the flag, the opt-in, availability, the engine or the download may have changed.
    public var changesPublisher: AnyPublisher<Void, Never> {
        let installerChanges = downloadableModel?.installer.statePublisher.map { _ in () }.eraseToAnyPublisher()
            ?? Empty().eraseToAnyPublisher()
        return Publishers.Merge6(
            availabilityPublisher.map { _ in () },
            $downloadableModelAvailability.removeDuplicates().map { _ in () },
            storage.pageSummariesModelPublisher.map { _ in () },
            featureFlagUpdates,
            engineOverrideUpdates,
            installerChanges
        )
        .eraseToAnyPublisher()
    }

    public func refreshAvailability() {
        let isEnabled = isFeatureEnabled
        let latest = isEnabled ? engine.availability : Self.uncheckedAvailability
        if latest != availability {
            availability = latest
        }
        let latestDownloadable = isEnabled ? (downloadableModel?.engine.availability ?? .deviceNotEligible) : Self.uncheckedAvailability
        if latestDownloadable != downloadableModelAvailability {
            downloadableModelAvailability = latestDownloadable
        }
        // The flag decides downloads too: one in progress waits while it's off.
        if isEnabled, downloadableModelAvailability.isAvailable {
            downloadableModel?.installer.resumeIfNeeded()
        } else {
            downloadableModel?.installer.pause()
        }
        pushStateIfChanged()
    }

    /// Turns on Apple Intelligence.
    public func optIn() {
        setPageSummariesModel(.appleIntelligence)
    }

    /// Turns off Apple Intelligence.
    public func optOut() {
        setPageSummariesModel(.duckAI)
    }

    /// The user's own choice. Sends `selected` only when the choice changes, so the prompt and
    /// Settings count a change once even when both happen.
    public func select(_ model: AIChatPageSummariesModel, source: AIChatLocalModelPixel.SelectionSource) {
        guard storage.pageSummariesModel != model else { return }
        setPageSummariesModel(model)
        instrumentation?.fire(.selected(model, source: source))
    }

    /// Starts or retries the downloadable model's download.
    public func installDownloadableModel() {
        downloadableModel?.installer.install()
    }

    /// Stops a download in progress and deletes what was downloaded.
    public func cancelDownloadableModelInstall() {
        downloadableModel?.installer.cancel()
    }

    /// Ends runs, frees the model's memory, then deletes it.
    public func uninstallDownloadableModel() {
        guard let downloadableModel else { return }
        if activeEngineKind == .llama {
            runQueue.cancelEveryRun()
        }
        downloadableModel.engine.unloadModel()
        downloadableModel.installer.uninstall()
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
        return AIChatLocalModelConfig(state: state, tasks: Self.supportedTasks, model: model)
    }

    public func register(_ pusher: AIChatLocalModelPushing) {
        pushers.removeAll { $0.pusher == nil || $0.pusher === pusher }
        pushers.append(WeakPusher(pusher: pusher))
    }

    private var livePushers: [AIChatLocalModelPushing] {
        pushers.compactMap(\.pusher)
    }

    public func startRun(_ request: AIChatLocalRunRequest, for pusher: AIChatLocalModelPushing) throws -> AIChatLocalRunStartReply {
        refreshAvailability()
        guard currentState == .ready else {
            throw AIChatLocalModelRequestError.unavailable
        }
        guard !request.requestId.isEmpty, !request.content.isEmpty else {
            throw AIChatLocalModelRequestError.invalidArguments
        }
        let pageID = pusher.localModelPageID
        runQueue.enqueue(request, ownerID: pageID) { [weak self] chunk in
            self?.pushRunChunk(chunk, toPage: pageID)
        }
        // The pixels only know the cloud and Apple Intelligence, so a downloaded model's run would count as a cloud one.
        if activeEngineKind == .appleIntelligence {
            instrumentation?.fire(.runStarted(engine: storage.pageSummariesModel, task: request.task))
        }
        return AIChatLocalRunStartReply(model: model)
    }

    /// Only the script registered last for the page gets the chunk, so a page whose old script
    /// is still around doesn't see a chunk twice.
    private func pushRunChunk(_ chunk: AIChatLocalRunChunk, toPage pageID: ObjectIdentifier) {
        livePushers.last { $0.localModelPageID == pageID }?.pushLocalRunChunk(chunk)
    }

    public func cancelRun(requestId: String, for pusher: AIChatLocalModelPushing) {
        runQueue.cancel(requestId: requestId, ownerID: pusher.localModelPageID)
    }

    /// Ends the runs of a page that's gone, identified by its `localModelPageID`.
    public func cancelRuns(ownerID: ObjectIdentifier) {
        runQueue.cancelAll(ownerID: ownerID)
    }

    /// `ask` shows the platform's prompt. It isn't called when the model is already on, or downloading.
    /// For a downloadable model, Install answers `installing`: this summary uses the cloud, and the
    /// state pushes tell Duck.ai when the model is ready.
    public func requestAccess(ask: @MainActor (AIChatLocalModelAccessRequest) async -> AIChatLocalModelAccessReply.Result) async throws -> AIChatLocalModelAccessReply.Result {
        refreshAvailability()
        guard let state = currentState, state != .unsupported else {
            throw AIChatLocalModelRequestError.unavailable
        }

        switch activeEngineKind {
        case .appleIntelligence:
            if state == .ready { return .allowed }
            let result = await ask(.connect(model))
            if result == .allowed {
                select(.appleIntelligence, source: .duckAIPromo)
            }
            return result
        case .llama:
            switch state {
            case .ready: return .allowed
            case .downloading: return .installing
            case .notSetUp, .unsupported: break
            }
            guard let downloadableModel else { throw AIChatLocalModelRequestError.unavailable }
            let result = await ask(.install(model, bytes: downloadableModel.installer.spec.bytes))
            guard result == .allowed else { return result }
            downloadableModel.installer.install()
            return .installing
        }
    }

    // MARK: - Pixels

    /// The state pixel is daily, so sending it at launch, on every return to the app and on flag
    /// updates counts each person once a day, including one whose flag turns on mid-session.
    private func refreshAvailabilityAndReportState() {
        refreshAvailability()
        reportState()
    }

    /// Not while the downloaded model is the engine: `selected` would say cloud for someone using it.
    private func reportState() {
        guard let state = currentState, activeEngineKind == .appleIntelligence else { return }
        instrumentation?.fire(.state(selected: storage.pageSummariesModel, state: state, availability: availability))
    }

    // MARK: - Pushes

    private var pushedState: PushedState {
        PushedState(update: currentState.map { AIChatLocalModelStateUpdate(state: $0, errorCode: setupError) }, engine: activeEngineKind)
    }

    private func pushStateIfChanged() {
        let state = pushedState
        guard state != lastPushed else { return }
        let engineChanged = state.engine != lastPushed?.engine
        lastPushed = state
        // Turn Off, the flag, Apple Intelligence and a switch of engine decide every run,
        // including ones already started.
        if state.update?.state != .ready || engineChanged {
            runQueue.cancelEveryRun()
        }
        // With the flag off Duck.ai treats the model as unsupported, so tell open pages exactly that.
        let update = state.update ?? AIChatLocalModelStateUpdate(state: .unsupported)
        for pusher in livePushers {
            pusher.pushLocalModelState(update)
        }
    }
}

private struct WeakPusher {
    weak var pusher: AIChatLocalModelPushing?
}

/// Lets the run queue use whichever engine is active when a run starts.
private final class RoutingEngine: AIChatLocalModelEngine {

    var activeEngine: () -> AIChatLocalModelEngine? = { nil }

    var model: AIChatLocalModelInfo {
        activeEngine()?.model ?? AppleFoundationModelEngine.modelInfo
    }

    var availability: AIChatLocalModelAvailability {
        activeEngine()?.availability ?? .unsupportedOS
    }

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        guard let engine = activeEngine() else {
            return AsyncThrowingStream { $0.finish(throwing: AIChatLocalModelEngineError(code: .modelUnavailable)) }
        }
        return engine.run(request)
    }
}
