//
//  GeolocationProvider.swift
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

import CoreLocation
import Foundation

@MainActor
public final class GeolocationProvider {

    public typealias ContextProvider = (GeolocationFrame) -> SitePermissionRequestContext?
    public typealias PermissionRequestHandler = (SitePermissionRequestContext, @escaping (SitePermissionResolution) -> Void) -> Void
    public typealias PermissionQueryHandler = (SitePermissionRequestContext) -> SitePermissionQueryState

    private final class RetainedFrame {
        let context: SitePermissionRequestContext
        let frame: GeolocationFrame?

        init(context: SitePermissionRequestContext, frame: GeolocationFrame) {
            self.context = context
            self.frame = frame
        }

        init(context: SitePermissionRequestContext) {
            self.context = context
            frame = nil
        }
    }

    private final class OneShotRequest {
        let retainedFrame: RetainedFrame
        let options: GeolocationRequestOptions
        let completion: (GeolocationPositionResult) -> Void
        var isAuthorized = false
        var acquisitionStartedAt: Date?
        var timeoutTask: Task<Void, Never>?

        init(retainedFrame: RetainedFrame,
             options: GeolocationRequestOptions,
             completion: @escaping (GeolocationPositionResult) -> Void) {
            self.retainedFrame = retainedFrame
            self.options = options
            self.completion = completion
        }
    }

    @MainActor
    private final class Watch {
        weak var userScript: GeolocationUserScript?
        let retainedFrame: RetainedFrame
        let options: GeolocationRequestOptions
        let deliver: @MainActor (GeolocationPositionResult) -> Bool
        let deliverTerminal: @MainActor (GeolocationPositionResult) -> Bool
        var isAuthorized = false
        var acquisitionStartedAt: Date?
        var hasDeliveredPosition = false
        var timeoutTask: Task<Void, Never>?

        init(userScript: GeolocationUserScript,
             requestID: String,
             retainedFrame: RetainedFrame,
             options: GeolocationRequestOptions) {
            self.userScript = userScript
            self.retainedFrame = retainedFrame
            self.options = options
            deliver = { [weak userScript] result in
                userScript?.send(result, toWatchWithID: requestID) == true
            }
            deliverTerminal = { [weak userScript] result in
                userScript?.sendTerminal(result, toWatchWithID: requestID) == true
            }
        }

        init(retainedFrame: RetainedFrame,
             options: GeolocationRequestOptions,
             deliver: @escaping @MainActor (GeolocationPositionResult) -> Bool) {
            self.retainedFrame = retainedFrame
            self.options = options
            self.deliver = deliver
            deliverTerminal = deliver
        }
    }

    private enum Message {
        static let denied = "Location permission was denied"
        static let unavailable = "Location is unavailable"
        static let timeout = "Geolocation request timed out"
    }

    private let systemPermissionClient: SystemPermissionClient
    private let contextProvider: ContextProvider
    private let requestPermission: PermissionRequestHandler
    private let queryPermission: PermissionQueryHandler

    private var oneShotRequests = [UUID: OneShotRequest]()
    private var watches = [String: Watch]()
    private var queryFrames = [UUID: RetainedFrame]()
    private var locationUpdateHandlerID: UUID?
    private var latestLocation: CLLocation?
    private var isClosed = false

    public init(systemPermissionClient: SystemPermissionClient,
                contextProvider: @escaping ContextProvider,
                requestPermission: @escaping PermissionRequestHandler,
                queryPermission: @escaping PermissionQueryHandler) {
        self.systemPermissionClient = systemPermissionClient
        self.contextProvider = contextProvider
        self.requestPermission = requestPermission
        self.queryPermission = queryPermission
    }

    /// Returns the active native context for coordinator validation.
    public func currentContext(tabID: String, requestingFrameID: UInt64) -> SitePermissionRequestContext? {
        let retainedFrames = oneShotRequests.values.map(\.retainedFrame)
            + watches.values.map(\.retainedFrame)
            + queryFrames.values
        return retainedFrames.lazy
            .filter { $0.context.tabID == tabID && $0.context.requestingFrameID == requestingFrameID }
            .compactMap(validatedContext)
            .first
    }

    /// Cancels work belonging to the current page without permanently closing the provider.
    public func cancelPageActivity() {
        let scripts = watches.values.compactMap(\.userScript)
        watches.values.forEach { $0.timeoutTask?.cancel() }
        watches.removeAll()
        scripts.forEach { $0.cancelAllWatches() }

        let requestIDs = Array(oneShotRequests.keys)
        requestIDs.forEach {
            finishOneShot($0, with: .failure(.init(code: .positionUnavailable, message: Message.unavailable)))
        }
        queryFrames.removeAll()
        updateLocationSubscription()
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        cancelPageActivity()
    }

    private func retainedFrame(for frame: GeolocationFrame,
                               constraints: GeolocationRequestConstraints) -> RetainedFrame? {
        guard !isClosed,
              constraints.allowsRequest,
              let context = contextProvider(frame),
              context.requestingFrameID == frame.requestingFrameID else { return nil }
        return RetainedFrame(context: context, frame: frame)
    }

    private func validatedContext(_ retainedFrame: RetainedFrame) -> SitePermissionRequestContext? {
        guard let frame = retainedFrame.frame else { return retainedFrame.context }
        guard retainedFrame.context.requestingFrameID == frame.requestingFrameID,
              contextProvider(frame) == retainedFrame.context else { return nil }
        return retainedFrame.context
    }

    private func requestCurrentPosition(in retainedFrame: RetainedFrame,
                                        options: GeolocationRequestOptions) async -> GeolocationPositionResult {
        await withCheckedContinuation { continuation in
            let identifier = UUID()
            let request = OneShotRequest(retainedFrame: retainedFrame, options: options) { result in
                continuation.resume(returning: result)
            }
            oneShotRequests[identifier] = request
            requestPermission(retainedFrame.context) { [weak self] resolution in
                self?.resolvePermission(forOneShot: identifier, resolution: resolution)
            }
        }
    }

    private func resolvePermission(forOneShot identifier: UUID, resolution: SitePermissionResolution) {
        guard let request = oneShotRequests[identifier] else { return }
        guard resolution == .grant, validatedContext(request.retainedFrame) != nil else {
            finishOneShot(identifier, with: .failure(.init(code: .permissionDenied, message: Message.denied)))
            return
        }

        request.isAuthorized = true
        request.acquisitionStartedAt = Date()
        if let location = reusableLocation(maximumAge: request.options.maximumAge) {
            finishOneShot(identifier, with: .success(.init(location: location)))
        } else {
            scheduleOneShotTimeout(identifier, after: request.options.timeout)
            updateLocationSubscription()
        }
    }

    private func finishOneShot(_ identifier: UUID, with result: GeolocationPositionResult) {
        guard let request = oneShotRequests.removeValue(forKey: identifier) else { return }
        request.timeoutTask?.cancel()
        request.completion(result)
        updateLocationSubscription()
    }

    private func scheduleOneShotTimeout(_ identifier: UUID, after timeout: TimeInterval?) {
        guard let timeout, timeout.isFinite else { return }
        oneShotRequests[identifier]?.timeoutTask = timeoutTask(after: timeout) { [weak self] in
            self?.finishOneShot(identifier, with: .failure(.init(code: .timeout, message: Message.timeout)))
        }
    }

    private func resolvePermission(forWatch requestID: String, resolution: SitePermissionResolution) {
        guard let watch = watches[requestID] else { return }
        guard resolution == .grant, validatedContext(watch.retainedFrame) != nil else {
            send(.failure(.init(code: .permissionDenied, message: Message.denied)), toWatch: requestID, thenRemove: true)
            return
        }

        watch.isAuthorized = true
        watch.acquisitionStartedAt = Date()
        if let location = reusableLocation(maximumAge: watch.options.maximumAge) {
            send(.success(.init(location: location)), toWatch: requestID)
            watch.hasDeliveredPosition = true
        } else {
            scheduleWatchTimeout(requestID, after: watch.options.timeout)
        }
        updateLocationSubscription()
    }

    private func scheduleWatchTimeout(_ requestID: String, after timeout: TimeInterval?) {
        guard let timeout, timeout.isFinite, let watch = watches[requestID] else { return }
        watch.timeoutTask?.cancel()
        watch.timeoutTask = timeoutTask(after: timeout) { [weak self] in
            self?.send(.failure(.init(code: .timeout, message: Message.timeout)), toWatch: requestID)
        }
    }

    private func send(_ result: GeolocationPositionResult, toWatch requestID: String, thenRemove: Bool = false) {
        guard let watch = watches[requestID] else { return }
        watch.timeoutTask?.cancel()
        let wasDelivered = thenRemove ? watch.deliverTerminal(result) : watch.deliver(result)
        if thenRemove || !wasDelivered {
            watches.removeValue(forKey: requestID)
            updateLocationSubscription()
        }
    }

    private func updateLocationSubscription() {
        let needsUpdates = oneShotRequests.values.contains(where: \.isAuthorized)
            || watches.values.contains(where: \.isAuthorized)
        let needsHighAccuracy = oneShotRequests.values.contains {
            $0.isAuthorized && $0.options.enableHighAccuracy
        } || watches.values.contains {
            $0.isAuthorized && $0.options.enableHighAccuracy
        }
        if needsUpdates, locationUpdateHandlerID == nil {
            locationUpdateHandlerID = systemPermissionClient.addLocationUpdateHandler(
                highAccuracy: needsHighAccuracy
            ) { [weak self] update in
                self?.handleLocationUpdate(update)
            }
        } else if needsUpdates, let locationUpdateHandlerID {
            systemPermissionClient.updateLocationUpdateHandler(locationUpdateHandlerID,
                                                               highAccuracy: needsHighAccuracy)
        } else if !needsUpdates, let locationUpdateHandlerID {
            systemPermissionClient.removeLocationUpdateHandler(locationUpdateHandlerID)
            self.locationUpdateHandlerID = nil
        }
    }

    private func handleLocationUpdate(_ update: SystemPermissionClient.LocationUpdate) {
        switch update {
        case .success(let location):
            guard isValid(location) else { return }
            latestLocation = location
            let oneShotIDs = oneShotRequests.filter { $0.value.isAuthorized }.map(\.key)
            oneShotIDs.forEach { identifier in
                guard let request = oneShotRequests[identifier], validatedContext(request.retainedFrame) != nil else {
                    finishOneShot(identifier, with: .failure(.init(code: .positionUnavailable, message: Message.unavailable)))
                    return
                }
                guard isUsable(location,
                               after: request.acquisitionStartedAt,
                               maximumAge: request.options.maximumAge) else { return }
                finishOneShot(identifier, with: .success(.init(location: location)))
            }

            let watchIDs = watches.filter { $0.value.isAuthorized }.map(\.key)
            watchIDs.forEach { requestID in
                guard let watch = watches[requestID], validatedContext(watch.retainedFrame) != nil else {
                    send(.failure(.init(code: .positionUnavailable, message: Message.unavailable)),
                         toWatch: requestID,
                         thenRemove: true)
                    return
                }
                guard watch.hasDeliveredPosition
                        || isUsable(location,
                                    after: watch.acquisitionStartedAt,
                                    maximumAge: watch.options.maximumAge) else { return }
                send(.success(.init(location: location)), toWatch: requestID)
                watch.hasDeliveredPosition = true
            }
            updateLocationSubscription()
        case .failure(let error) where isPermissionDenied(error):
            let permissionDenied = GeolocationPositionResult.failure(
                .init(code: .permissionDenied, message: Message.denied)
            )
            let oneShotIDs = oneShotRequests.filter { $0.value.isAuthorized }.map(\.key)
            oneShotIDs.forEach { finishOneShot($0, with: permissionDenied) }
            Array(watches.filter { $0.value.isAuthorized }.keys).forEach {
                send(permissionDenied, toWatch: $0, thenRemove: true)
            }
        case .failure(let error) where isLocationUnknown(error):
            break
        case .failure:
            let oneShotIDs = oneShotRequests.filter { $0.value.isAuthorized }.map(\.key)
            oneShotIDs.forEach {
                finishOneShot($0, with: .failure(.init(code: .positionUnavailable, message: Message.unavailable)))
            }
            watches.filter { $0.value.isAuthorized }.keys.forEach {
                send(.failure(.init(code: .positionUnavailable, message: Message.unavailable)), toWatch: $0)
            }
        }
    }

    private func reusableLocation(maximumAge: TimeInterval) -> CLLocation? {
        guard maximumAge > 0, let latestLocation, isValid(latestLocation) else { return nil }
        return max(0, Date().timeIntervalSince(latestLocation.timestamp)) <= maximumAge ? latestLocation : nil
    }

    private func isUsable(_ location: CLLocation,
                          after acquisitionStartedAt: Date?,
                          maximumAge: TimeInterval) -> Bool {
        guard isValid(location), let acquisitionStartedAt else { return false }
        guard maximumAge.isFinite else { return true }
        return location.timestamp >= acquisitionStartedAt.addingTimeInterval(-maximumAge)
    }

    private func isValid(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 && CLLocationCoordinate2DIsValid(location.coordinate)
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == kCLErrorDomain && error.code == CLError.Code.denied.rawValue
    }

    private func isLocationUnknown(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == kCLErrorDomain && error.code == CLError.Code.locationUnknown.rawValue
    }

    private func timeoutTask(after timeout: TimeInterval,
                             action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            let maximumSeconds = TimeInterval(60 * 60 * 24 * 365 * 100)
            let nanoseconds = UInt64(min(max(0, timeout), maximumSeconds) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                action()
            } catch {
                // Cancellation is the expected completion path after a result or page change.
            }
        }
    }

    // These frame-free entry points keep the location lifecycle independently testable from WebKit.
    func requestCurrentPosition(context: SitePermissionRequestContext,
                                options: GeolocationRequestOptions = .init()) async -> GeolocationPositionResult {
        await requestCurrentPosition(in: RetainedFrame(context: context), options: options)
    }

    func startWatch(withID requestID: String,
                    context: SitePermissionRequestContext,
                    options: GeolocationRequestOptions = .init(),
                    deliver: @escaping @MainActor (GeolocationPositionResult) -> Bool) {
        guard !isClosed, watches[requestID] == nil else { return }
        let retainedFrame = RetainedFrame(context: context)
        watches[requestID] = Watch(retainedFrame: retainedFrame, options: options, deliver: deliver)
        requestPermission(context) { [weak self] resolution in
            self?.resolvePermission(forWatch: requestID, resolution: resolution)
        }
    }

    func cancelWatch(withID requestID: String) {
        guard let watch = watches.removeValue(forKey: requestID) else { return }
        watch.timeoutTask?.cancel()
        updateLocationSubscription()
    }
}

// MARK: - GeolocationUserScriptDelegate

extension GeolocationProvider: GeolocationUserScriptDelegate {

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      getCurrentPositionWith options: GeolocationRequestOptions,
                                      constraints: GeolocationRequestConstraints,
                                      in frame: GeolocationFrame) async -> GeolocationPositionResult {
        guard let retainedFrame = retainedFrame(for: frame, constraints: constraints) else {
            return .failure(.init(code: .permissionDenied, message: Message.denied))
        }
        return await requestCurrentPosition(in: retainedFrame, options: options)
    }

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      constraints: GeolocationRequestConstraints,
                                      permissionStateIn frame: GeolocationFrame) -> GeolocationPermissionState {
        guard let retainedFrame = retainedFrame(for: frame, constraints: constraints) else { return .denied }
        let identifier = UUID()
        queryFrames[identifier] = retainedFrame
        defer { queryFrames.removeValue(forKey: identifier) }

        return queryPermission(retainedFrame.context)
    }

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      didStartWatchWithID requestID: String,
                                      options: GeolocationRequestOptions,
                                      constraints: GeolocationRequestConstraints,
                                      in frame: GeolocationFrame) {
        guard watches[requestID] == nil else { return }
        guard let retainedFrame = retainedFrame(for: frame, constraints: constraints) else {
            _ = userScript.sendTerminal(.failure(.init(code: .permissionDenied, message: Message.denied)), toWatchWithID: requestID)
            return
        }

        watches[requestID] = Watch(userScript: userScript, requestID: requestID, retainedFrame: retainedFrame, options: options)
        requestPermission(retainedFrame.context) { [weak self] resolution in
            self?.resolvePermission(forWatch: requestID, resolution: resolution)
        }
    }

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      didCancelWatchWithID requestID: String) {
        guard let watch = watches.removeValue(forKey: requestID) else { return }
        watch.timeoutTask?.cancel()
        updateLocationSubscription()
    }
}
