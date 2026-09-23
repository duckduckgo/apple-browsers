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
import os.log

extension Logger {
    static let sitePermissions = Logger(subsystem: "SitePermissions", category: "Geolocation")
}

/// Handles a tab's location requests and ongoing location updates after checking site and system permissions.
/// It shares the system location service while keeping each page's requests, timeouts, and permission subscriptions separate.
@MainActor
public final class GeolocationProvider {

    public typealias ContextProvider = (GeolocationFrame) -> SitePermissionRequestContext?
    public typealias PermissionRequestHandler = (SitePermissionRequestContext, @escaping (SitePermissionResolution) -> Void) -> Void
    public typealias PermissionQueryHandler = (SitePermissionRequestContext) -> SitePermissionQueryState

    /// Keeps the original permission context and WebKit frame so later callbacks can detect a changed page or frame.
    /// Tests can supply just the context when they do not need WebKit validation.
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

    /// Tracks one `getCurrentPosition()` call, which completes with a single location reading or an error.
    /// It keeps the permission decision and timeout state while the request waits or the tab is inactive.
    private final class OneShotRequest {
        let retainedFrame: RetainedFrame
        let options: GeolocationRequestOptions
        let completion: (GeolocationPositionResult) -> Void
        var hasRequestedPermission = false
        var resolution: SitePermissionResolution?
        var isAuthorized: Bool { resolution == .grant }
        var acquisitionStartedAt: Date?
        var remainingTimeout: TimeInterval?
        var timeoutStartedAt: TimeInterval?
        var timeoutTask: Task<Void, Never>?

        init(retainedFrame: RetainedFrame,
             options: GeolocationRequestOptions,
             completion: @escaping (GeolocationPositionResult) -> Void) {
            self.retainedFrame = retainedFrame
            self.options = options
            self.completion = completion
            remainingTimeout = options.timeout
        }
    }

    /// Tracks a page's `navigator.permissions.query()` result so its state can change when permissions change.
    /// Observing permission state does not itself request location access or start location updates.
    @MainActor
    private final class PermissionStatus {
        weak var userScript: GeolocationUserScript?
        let retainedFrame: RetainedFrame
        let deliver: @MainActor (GeolocationPermissionState) -> Bool
        var lastState: GeolocationPermissionState

        init(userScript: GeolocationUserScript,
             statusID: String,
             retainedFrame: RetainedFrame,
             initialState: GeolocationPermissionState) {
            self.userScript = userScript
            self.retainedFrame = retainedFrame
            lastState = initialState
            deliver = { [weak userScript] state in
                userScript?.send(state, toPermissionStatusWithID: statusID) == true
            }
        }

        init(retainedFrame: RetainedFrame,
             initialState: GeolocationPermissionState,
             deliver: @escaping @MainActor (GeolocationPermissionState) -> Bool) {
            self.retainedFrame = retainedFrame
            lastState = initialState
            self.deliver = deliver
        }
    }

    /// Tracks a `watchPosition()` subscription that can receive multiple location readings.
    /// It keeps the callback and request state until cancellation, permission revocation, or page teardown.
    @MainActor
    private final class LocationSubscription {
        weak var userScript: GeolocationUserScript?
        let retainedFrame: RetainedFrame
        let options: GeolocationRequestOptions
        let deliver: @MainActor (GeolocationPositionResult) -> Bool
        let deliverTerminal: @MainActor (GeolocationPositionResult) -> Bool
        var hasRequestedPermission = false
        var resolution: SitePermissionResolution?
        var isAuthorized: Bool { resolution == .grant }
        var acquisitionStartedAt: Date?
        var remainingTimeout: TimeInterval?
        var timeoutStartedAt: TimeInterval?
        var hasDeliveredPosition = false
        var timeoutTask: Task<Void, Never>?

        init(userScript: GeolocationUserScript,
             requestID: String,
             retainedFrame: RetainedFrame,
             options: GeolocationRequestOptions) {
            self.userScript = userScript
            self.retainedFrame = retainedFrame
            self.options = options
            remainingTimeout = options.timeout
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
            remainingTimeout = options.timeout
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
    private var watches = [String: LocationSubscription]()
    private var permissionStatuses = [String: PermissionStatus]()
    private var locationUpdateHandlerID: UUID?
    // Cache the request's accuracy option, which can differ from the shared location manager's setting.
    private var latestLocation: (location: CLLocation, requestedHighAccuracy: Bool)?
    private var isActive = true
    private var resumedAt: Date?
    private var isClosed = false

    private var locationCaptureState = SitePermissionCaptureState.inactive
    var isLocationActive: Bool { locationCaptureState == .active }
    public var locationActivityHandler: ((SitePermissionCaptureState) -> Void)?

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
            + permissionStatuses.values.map(\.retainedFrame)
        return retainedFrames.lazy
            .filter { $0.context.tabID == tabID && $0.context.requestingFrameID == requestingFrameID }
            .compactMap(validatedContext)
            .first
    }

    /// Suspends acquisition and timeout budgets while the owning tab is not visible and active.
    /// Watches and permission decisions survive; resuming requires a new location reading.
    public func setIsActive(_ isActive: Bool) {
        guard !isClosed, self.isActive != isActive else { return }
        Logger.sitePermissions.debug("Location provider active: \(isActive, privacy: .public)")
        self.isActive = isActive
        if isActive {
            resumedAt = Date()
            systemPermissionClient.refreshAuthorizationStates()
            Array(oneShotRequests.keys).forEach(resumeOneShot)
            Array(watches.keys).forEach(resumeWatch)
        } else {
            latestLocation = nil
            let now = ProcessInfo.processInfo.systemUptime
            for request in oneShotRequests.values {
                request.timeoutTask?.cancel()
                if let startedAt = request.timeoutStartedAt, let remaining = request.remainingTimeout {
                    request.remainingTimeout = max(0, remaining - (now - startedAt))
                }
                request.timeoutStartedAt = nil
            }
            for watch in watches.values {
                watch.timeoutTask?.cancel()
                if let startedAt = watch.timeoutStartedAt, let remaining = watch.remainingTimeout {
                    watch.remainingTimeout = max(0, remaining - (now - startedAt))
                }
                watch.timeoutStartedAt = nil
            }
        }
        updateLocationSubscription()
    }

    /// Cancels work belonging to the current page without permanently closing the provider.
    public func cancelPageActivity() {
        Logger.sitePermissions.debug("Cancel page location activity: one-shots=\(self.oneShotRequests.count), watches=\(self.watches.count)")
        var scripts = [ObjectIdentifier: GeolocationUserScript]()
        (watches.values.compactMap(\.userScript) + permissionStatuses.values.compactMap(\.userScript)).forEach {
            scripts[ObjectIdentifier($0)] = $0
        }
        watches.values.forEach { $0.timeoutTask?.cancel() }
        watches.removeAll()
        permissionStatuses.removeAll()
        scripts.values.forEach { $0.cancelAllWatches() }

        let requestIDs = Array(oneShotRequests.keys)
        requestIDs.forEach {
            finishOneShot($0, with: .failure(.init(code: .positionUnavailable, message: Message.unavailable)))
        }
        updateLocationSubscription()
    }

    /// Re-evaluates every live page `PermissionStatus` against current native and policy state.
    public func refreshPermissionStatuses() {
        guard !isClosed else { return }

        for statusID in Array(permissionStatuses.keys) {
            guard let status = permissionStatuses[statusID] else { continue }
            guard let context = validatedContext(status.retainedFrame) else {
                if status.lastState != .denied {
                    _ = status.deliver(.denied)
                }
                permissionStatuses.removeValue(forKey: statusID)
                continue
            }
            let state = queryPermission(context)
            guard state != status.lastState else { continue }
            status.lastState = state
            if !status.deliver(state) {
                permissionStatuses.removeValue(forKey: statusID)
            }
        }
    }

    /// Stops page activity after an explicit permission denial or removal, then refreshes query state.
    public func revokeActivePermission() {
        guard !isClosed else { return }
        Logger.sitePermissions.debug("Revoke active location permission")
        let wasLocationActive = isLocationActive
        let denied = GeolocationPositionResult.failure(
            .init(code: .permissionDenied, message: Message.denied)
        )
        Array(oneShotRequests.keys).forEach { finishOneShot($0, with: denied) }
        Array(watches.keys).forEach { send(denied, toWatch: $0, thenRemove: true) }
        if !wasLocationActive {
            refreshPermissionStatuses()
        }
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
            Logger.sitePermissions.debug("getCurrentPosition received: request=\(identifier.uuidString, privacy: .public)")
            Logger.sitePermissions.debug("Location frame=\(String(retainedFrame.context.requestingFrameID), privacy: .private(mask: .hash)), navigation=\(retainedFrame.context.navigationGeneration)")
            Logger.sitePermissions.debug("Location options: highAccuracy=\(options.enableHighAccuracy), timeout=\(options.timeout ?? .infinity), maximumAge=\(options.maximumAge)")
            let request = OneShotRequest(retainedFrame: retainedFrame, options: options) { result in
                continuation.resume(returning: result)
            }
            oneShotRequests[identifier] = request
            resumeOneShot(identifier)
        }
    }

    private func resumeOneShot(_ identifier: UUID) {
        guard isActive, let request = oneShotRequests[identifier] else { return }
        if !request.hasRequestedPermission {
            request.hasRequestedPermission = true
            Logger.sitePermissions.debug("getCurrentPosition checking permission: request=\(identifier.uuidString, privacy: .public)")
            requestPermission(request.retainedFrame.context) { [weak self, weak request] resolution in
                Logger.sitePermissions.debug("getCurrentPosition permission: request=\(identifier.uuidString, privacy: .public), granted=\(resolution == .grant)")
                request?.resolution = resolution
                self?.refreshPermissionStatuses()
                self?.resumeOneShot(identifier)
                self?.updateLocationSubscription()
            }
            return
        }
        guard let resolution = request.resolution else { return }
        guard resolution == .grant,
              systemPermissionClient.authorizationState(for: .location) == .authorized,
              validatedContext(request.retainedFrame) != nil else {
            finishOneShot(identifier, with: .failure(.init(code: .permissionDenied, message: Message.denied)))
            return
        }

        request.acquisitionStartedAt = Date()
        if let location = reusableLocation(for: request.options) {
            // Report location use even when a cached position avoids starting Core Location.
            updateLocationActivity(.active)
            finishOneShot(identifier, with: .success(.init(location: location)))
        } else {
            scheduleOneShotTimeout(identifier, after: request.remainingTimeout)
            updateLocationSubscription()
        }
    }

    private func finishOneShot(_ identifier: UUID, with result: GeolocationPositionResult) {
        guard let request = oneShotRequests.removeValue(forKey: identifier) else { return }
        Logger.sitePermissions.debug("getCurrentPosition completed: request=\(identifier.uuidString, privacy: .public)")
        if case .failure(let error) = result {
            Logger.sitePermissions.debug("getCurrentPosition error: request=\(identifier.uuidString, privacy: .public), code=\(error.code.rawValue)")
        }
        request.timeoutTask?.cancel()
        request.completion(result)
        updateLocationSubscription()
    }

    private func scheduleOneShotTimeout(_ identifier: UUID, after timeout: TimeInterval?) {
        guard let timeout, timeout.isFinite else { return }
        oneShotRequests[identifier]?.timeoutStartedAt = ProcessInfo.processInfo.systemUptime
        oneShotRequests[identifier]?.timeoutTask = timeoutTask(after: timeout) { [weak self] in
            self?.finishOneShot(identifier, with: .failure(.init(code: .timeout, message: Message.timeout)))
        }
    }

    private func resumeWatch(_ requestID: String) {
        guard isActive, let watch = watches[requestID] else { return }
        if !watch.hasRequestedPermission {
            watch.hasRequestedPermission = true
            Logger.sitePermissions.debug("watchPosition checking permission: request=\(requestID, privacy: .private(mask: .hash))")
            requestPermission(watch.retainedFrame.context) { [weak self, weak watch] resolution in
                Logger.sitePermissions.debug("watchPosition permission: request=\(requestID, privacy: .private(mask: .hash)), granted=\(resolution == .grant)")
                watch?.resolution = resolution
                self?.refreshPermissionStatuses()
                self?.resumeWatch(requestID)
                self?.updateLocationSubscription()
            }
            return
        }
        guard let resolution = watch.resolution else { return }
        guard resolution == .grant,
              systemPermissionClient.authorizationState(for: .location) == .authorized,
              validatedContext(watch.retainedFrame) != nil else {
            send(.failure(.init(code: .permissionDenied, message: Message.denied)), toWatch: requestID, thenRemove: true)
            return
        }

        watch.acquisitionStartedAt = Date()
        if let location = reusableLocation(for: watch.options) {
            send(.success(.init(location: location)), toWatch: requestID)
            watch.hasDeliveredPosition = true
        } else {
            scheduleWatchTimeout(requestID, after: watch.remainingTimeout)
        }
        updateLocationSubscription()
    }

    private func scheduleWatchTimeout(_ requestID: String, after timeout: TimeInterval?) {
        guard let timeout, timeout.isFinite, let watch = watches[requestID] else { return }
        watch.timeoutTask?.cancel()
        watch.timeoutStartedAt = ProcessInfo.processInfo.systemUptime
        watch.timeoutTask = timeoutTask(after: timeout) { [weak self] in
            self?.send(.failure(.init(code: .timeout, message: Message.timeout)), toWatch: requestID)
        }
    }

    private func send(_ result: GeolocationPositionResult, toWatch requestID: String, thenRemove: Bool = false) {
        guard let watch = watches[requestID] else { return }
        if case .failure(let error) = result {
            Logger.sitePermissions.debug("watchPosition error: request=\(requestID, privacy: .private(mask: .hash)), code=\(error.code.rawValue)")
        } else if !watch.hasDeliveredPosition {
            Logger.sitePermissions.debug("watchPosition first position: request=\(requestID, privacy: .private(mask: .hash))")
        }
        watch.timeoutTask?.cancel()
        watch.timeoutStartedAt = nil
        watch.remainingTimeout = nil
        let wasDelivered = thenRemove ? watch.deliverTerminal(result) : watch.deliver(result)
        if thenRemove || !wasDelivered {
            Logger.sitePermissions.debug("watchPosition ended: request=\(requestID, privacy: .private(mask: .hash)), delivered=\(wasDelivered)")
            watches.removeValue(forKey: requestID)
            updateLocationSubscription()
        }
    }

    private func updateLocationSubscription() {
        let hasAuthorizedRequests = oneShotRequests.values.contains(where: \.isAuthorized)
            || watches.values.contains(where: \.isAuthorized)
        let needsUpdates = isActive
            && systemPermissionClient.authorizationState(for: .location) == .authorized
            && hasAuthorizedRequests
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
        // Suspension releases Core Location without ending the page's Allow Once grant.
        let state: SitePermissionCaptureState = needsUpdates ? .active : (!isActive && hasAuthorizedRequests ? .paused : .inactive)
        updateLocationActivity(state)
    }

    private func updateLocationActivity(_ state: SitePermissionCaptureState) {
        guard locationCaptureState != state else { return }
        Logger.sitePermissions.debug("Location activity: \(String(describing: self.locationCaptureState), privacy: .public) -> \(String(describing: state), privacy: .public)")
        locationCaptureState = state
        locationActivityHandler?(state)
        if state == .inactive {
            // Re-query after the activity callback so PermissionStatus also reflects any authorization change.
            refreshPermissionStatuses()
        }
    }

    private func handleLocationUpdate(_ update: SystemPermissionClient.LocationUpdate) {
        guard isActive else { return }
        switch update {
        case .success(let location):
            guard isValid(location) else { return }
            if let resumedAt, location.timestamp < resumedAt { return }
            let oneShotIDs = oneShotRequests.filter { $0.value.isAuthorized }.map(\.key)
            oneShotIDs.forEach { identifier in
                guard let request = oneShotRequests[identifier], validatedContext(request.retainedFrame) != nil else {
                    finishOneShot(identifier, with: .failure(.init(code: .positionUnavailable, message: Message.unavailable)))
                    return
                }
                guard isUsable(location,
                               after: request.acquisitionStartedAt,
                               maximumAge: request.options.maximumAge) else { return }
                latestLocation = (location, request.options.enableHighAccuracy)
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
                latestLocation = (location, watch.options.enableHighAccuracy)
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

    private func reusableLocation(for options: GeolocationRequestOptions) -> CLLocation? {
        guard options.maximumAge > 0,
              let latestLocation,
              latestLocation.requestedHighAccuracy == options.enableHighAccuracy,
              isValid(latestLocation.location) else { return nil }
        let location = latestLocation.location
        return max(0, Date().timeIntervalSince(location.timestamp)) <= options.maximumAge ? location : nil
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
                guard !Task.isCancelled else { return }
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
        watches[requestID] = LocationSubscription(retainedFrame: retainedFrame, options: options, deliver: deliver)
        resumeWatch(requestID)
    }

    func cancelWatch(withID requestID: String) {
        guard let watch = watches.removeValue(forKey: requestID) else { return }
        Logger.sitePermissions.debug("watchPosition cancelled: request=\(requestID, privacy: .private(mask: .hash))")
        watch.timeoutTask?.cancel()
        updateLocationSubscription()
    }

    func permissionState(withID statusID: String,
                         context: SitePermissionRequestContext,
                         deliver: @escaping @MainActor (GeolocationPermissionState) -> Bool) -> GeolocationPermissionState {
        guard !isClosed, permissionStatuses[statusID] == nil else { return .denied }
        let retainedFrame = RetainedFrame(context: context)
        let status = PermissionStatus(retainedFrame: retainedFrame,
                                      initialState: .denied,
                                      deliver: deliver)
        permissionStatuses[statusID] = status
        let state = queryPermission(context)
        status.lastState = state
        return state
    }
}

// MARK: - GeolocationUserScriptDelegate

extension GeolocationProvider: GeolocationUserScriptDelegate {

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      getCurrentPositionWith options: GeolocationRequestOptions,
                                      constraints: GeolocationRequestConstraints,
                                      in frame: GeolocationFrame) async -> GeolocationPositionResult {
        guard let retainedFrame = retainedFrame(for: frame, constraints: constraints) else {
            Logger.sitePermissions.debug("getCurrentPosition rejected: inactive or disallowed frame")
            return .failure(.init(code: .permissionDenied, message: Message.denied))
        }
        return await requestCurrentPosition(in: retainedFrame, options: options)
    }

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      permissionStatusID statusID: String,
                                      constraints: GeolocationRequestConstraints,
                                      permissionStateIn frame: GeolocationFrame) -> GeolocationPermissionState {
        guard let retainedFrame = retainedFrame(for: frame, constraints: constraints) else { return .denied }
        guard permissionStatuses[statusID] == nil else { return .denied }
        let status = PermissionStatus(userScript: userScript,
                                      statusID: statusID,
                                      retainedFrame: retainedFrame,
                                      initialState: .denied)
        permissionStatuses[statusID] = status
        let state = queryPermission(retainedFrame.context)
        status.lastState = state
        return state
    }

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      didStartWatchWithID requestID: String,
                                      options: GeolocationRequestOptions,
                                      constraints: GeolocationRequestConstraints,
                                      in frame: GeolocationFrame) {
        guard watches[requestID] == nil else { return }
        Logger.sitePermissions.debug("watchPosition received: request=\(requestID, privacy: .private(mask: .hash))")
        guard let retainedFrame = retainedFrame(for: frame, constraints: constraints) else {
            Logger.sitePermissions.debug("watchPosition rejected: inactive or disallowed frame")
            _ = userScript.sendTerminal(.failure(.init(code: .permissionDenied, message: Message.denied)), toWatchWithID: requestID)
            return
        }

        Logger.sitePermissions.debug("Location frame=\(String(retainedFrame.context.requestingFrameID), privacy: .private(mask: .hash)), navigation=\(retainedFrame.context.navigationGeneration)")
        watches[requestID] = LocationSubscription(userScript: userScript, requestID: requestID, retainedFrame: retainedFrame, options: options)
        resumeWatch(requestID)
    }

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      didCancelWatchWithID requestID: String) {
        cancelWatch(withID: requestID)
    }

    public func geolocationUserScript(_ userScript: GeolocationUserScript,
                                      didCancelPermissionStatusWithID statusID: String) {
        permissionStatuses.removeValue(forKey: statusID)
    }
}
