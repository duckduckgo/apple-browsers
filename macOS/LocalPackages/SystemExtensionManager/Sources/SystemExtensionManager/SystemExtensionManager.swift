//
//  SystemExtensionManager.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Cocoa
import Combine
import os.log
import SystemExtensions

protocol SystemExtensionRequestManaging: AnyObject {
    func submitRequest(_ request: OSSystemExtensionRequest)
}

extension OSSystemExtensionManager: SystemExtensionRequestManaging {}

public enum SystemExtensionRequestError: Error, Equatable {
    case unknownRequestResult
    case willActivateAfterReboot
    case requestTimedOut
}

public enum SystemExtensionActivationState: Equatable {
    case enabled
    case awaitingUserApproval
    case disabled
    case uninstalling
    case notInstalled
    case unknown
}

public struct SystemExtensionPropertiesSnapshot: Equatable {
    let isEnabled: Bool
    let isAwaitingUserApproval: Bool
    let isUninstalling: Bool

    public init(isEnabled: Bool, isAwaitingUserApproval: Bool, isUninstalling: Bool) {
        self.isEnabled = isEnabled
        self.isAwaitingUserApproval = isAwaitingUserApproval
        self.isUninstalling = isUninstalling
    }
}

public struct SystemExtensionManager {

    private static let defaultRequestTimeout: TimeInterval = 120
    private static let networkExtensionSettingsExtensionPointIdentifier = "com.apple.system_extension.network_extension.extension-point"

    static func systemSettingsURLString(forExtensionWithIdentifier extensionBundleID: String) -> String {
        if #available(macOS 15, *) {
            let extensionPointIdentifier = percentEncodedQueryValue(networkExtensionSettingsExtensionPointIdentifier)
            let extensionIdentifier = percentEncodedQueryValue(extensionBundleID)
            return "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=\(extensionPointIdentifier)&extensionIdentifier=\(extensionIdentifier)"
        } else {
            return "x-apple.systempreferences:com.apple.preference.security?Security"
        }
    }

    private let extensionBundleID: String
    private let manager: any SystemExtensionRequestManaging
    private let workspace: NSWorkspace
    private let requestTimeout: TimeInterval

    public init(
        extensionBundleID: String,
        manager: OSSystemExtensionManager = .shared,
        workspace: NSWorkspace = .shared) {

        self.init(
            extensionBundleID: extensionBundleID,
            manager: manager as any SystemExtensionRequestManaging,
            workspace: workspace,
            requestTimeout: Self.defaultRequestTimeout)
    }

    init(
        extensionBundleID: String,
        manager: any SystemExtensionRequestManaging,
        workspace: NSWorkspace = .shared,
        requestTimeout: TimeInterval = Self.defaultRequestTimeout) {

        self.extensionBundleID = extensionBundleID
        self.manager = manager
        self.workspace = workspace
        self.requestTimeout = requestTimeout
    }

    /// - Returns: The system extension version when it's updated, otherwise `nil`.
    ///
    public func activate(waitingForUserApproval: @escaping () -> Void) async throws -> String? {

        workaroundToActivateBeforeSequoia()

        let activationRequest = SystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            manager: manager,
            waitingForUserApproval: waitingForUserApproval,
            requestTimeout: requestTimeout)

        try await activationRequest.submit()

        return activationRequest.version
    }

    /// Workaround to help make activation easier for users.
    ///
    /// Documenting a workaround for the issue discussed in https://app.asana.com/0/0/1205275221447702/f
    ///
    /// ## Background:
    ///
    /// For a lot of users, the system won't show the system-extension-blocked alert if there's a previous request
    /// to activate the extension.  You can see active requests in your console using command
    /// `systemextensionsctl list`.
    ///
    /// Proposed workaround: Just open system settings into the right section when we detect a previous
    /// activation request already exists.
    ///
    /// ## Tradeoffs
    ///
    /// Unfortunately we don't know if the previous request was sent out by the currently runing-instance of this App
    /// or if an activation request was made, and then the App was reopened.
    ///
    /// This means we don't know if we'll be notified when the previous activation request completes or fails.  Because we
    /// need to update our UI once the extension is allowed, we can't avoid sending a new activation request every time.
    ///
    /// For the users that don't see the alert come up more than once this should be invisible.  For users (like myself) that
    /// see the alert every single time, they'll see both the alert and system settings being opened automatically.
    ///
    private func workaroundToActivateBeforeSequoia() {
        if hasPendingActivationRequests() {
            openSystemSettingsSecurity()
        }
    }

    public func deactivate() async throws {
        try await SystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            manager: manager,
            requestTimeout: requestTimeout)
        .submit()
    }

    public func openSystemExtensionSettings() {
        openSystemSettingsSecurity()
    }

    public func activationState() async -> SystemExtensionActivationState {
        do {
            let properties = try await SystemExtensionPropertiesRequest.properties(
                forExtensionWithIdentifier: extensionBundleID,
                manager: manager,
                requestTimeout: requestTimeout
            )
            let snapshots = properties.map {
                SystemExtensionPropertiesSnapshot(
                    isEnabled: $0.isEnabled,
                    isAwaitingUserApproval: $0.isAwaitingUserApproval,
                    isUninstalling: $0.isUninstalling
                )
            }
            return Self.activationState(from: snapshots)
        } catch is CancellationError {
            return .unknown
        } catch {
            Logger.systemExtensionManager.error("""
            Failed to query system extension state
              bundleID:    \(extensionBundleID, privacy: .public)
              description: \(error.localizedDescription, privacy: .public)
            """)
            return .unknown
        }
    }

    static func activationState(from properties: [SystemExtensionPropertiesSnapshot]) -> SystemExtensionActivationState {
        guard !properties.isEmpty else {
            return .notInstalled
        }

        if properties.contains(where: \.isEnabled) {
            return .enabled
        }

        if properties.contains(where: \.isUninstalling) {
            return .uninstalling
        }

        if properties.contains(where: \.isAwaitingUserApproval) {
            return .awaitingUserApproval
        }

        return .disabled
    }

    @available(macOS 15.1, *)
    public func makeActivationStateObserver(onStateChange: @escaping () -> Void) -> SystemExtensionActivationStateObserver {
        SystemExtensionActivationStateObserver(extensionBundleID: extensionBundleID, onStateChange: onStateChange)
    }

    // MARK: - Activation: Checking if there are pending requests

    /// Checks if there are pending activation requests for the system extension.
    ///
    /// This implementation should work well for all macOS 11+ releases.  A better implementation for macOS 12+
    /// would be to use a properties request, but that option requires bigger changes and some rethinking of these
    /// classes which I'd rather avoid right now.  In short this solution was picked as a quick solution with the best
    /// ROI to avoid getting blocked.
    ///
    private func hasPendingActivationRequests() -> Bool {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.launchPath = "/bin/bash" // Specify the shell to use
        task.arguments = ["-c", "$(which systemextensionsctl) list | $(which egrep) -c '(?:\(extensionBundleID)).+(?:activated waiting for user)+'"]

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return (Int(output ?? "0") ?? 0) > 0
    }

    private func openSystemSettingsSecurity() {
        let url = URL(string: Self.systemSettingsURLString(forExtensionWithIdentifier: extensionBundleID))!
        workspace.open(url)
    }

    private static func percentEncodedQueryValue(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }
}

private final class SystemExtensionPropertiesRequest: NSObject {

    private let request: OSSystemExtensionRequest
    private let manager: any SystemExtensionRequestManaging
    private let requestTimeout: TimeInterval
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[OSSystemExtensionProperties], Error>?
    private var timeoutTask: Task<Void, Never>?
    private var cancellationWasRequested = false

    private init(request: OSSystemExtensionRequest,
                 manager: any SystemExtensionRequestManaging,
                 requestTimeout: TimeInterval) {
        self.request = request
        self.manager = manager
        self.requestTimeout = requestTimeout
        super.init()
    }

    static func properties(forExtensionWithIdentifier bundleId: String,
                           manager: any SystemExtensionRequestManaging,
                           requestTimeout: TimeInterval) async throws -> [OSSystemExtensionProperties] {
        let query = SystemExtensionPropertiesRequest(
            request: .propertiesRequest(forExtensionWithIdentifier: bundleId, queue: .global()),
            manager: manager,
            requestTimeout: requestTimeout
        )
        // OSSystemExtensionRequest.delegate is weak. Without an explicit lifetime extension,
        // the compiler may release `query` during the await, niling the delegate before the
        // callback fires and leaving the continuation suspended forever.
        let result = try await query.submit()
        return withExtendedLifetime(query) { result }
    }

    private func submit() async throws -> [OSSystemExtensionProperties] {
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                submit(with: continuation)
            }
        } onCancel: {
            complete(with: .failure(CancellationError()))
        }
    }

    private func submit(with continuation: CheckedContinuation<[OSSystemExtensionProperties], Error>) {
        lock.lock()
        assert(self.continuation == nil, "Request can only be submitted once")
        guard !cancellationWasRequested else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }

        self.continuation = continuation
        timeoutTask = makeTimeoutTask()
        lock.unlock()

        request.delegate = self

        guard !Task.isCancelled else {
            complete(with: .failure(CancellationError()))
            return
        }

        manager.submitRequest(request)
    }

    private func makeTimeoutTask() -> Task<Void, Never> {
        let requestTimeout = max(0, requestTimeout)

        return Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(requestTimeout * Double(NSEC_PER_SEC)))
            guard !Task.isCancelled else {
                return
            }

            self?.complete(with: .failure(SystemExtensionRequestError.requestTimedOut))
        }
    }

    private func complete(with result: Result<[OSSystemExtensionProperties], Error>) {
        lock.lock()
        let pendingContinuation = continuation
        continuation = nil
        let pendingTimeoutTask = timeoutTask
        timeoutTask = nil
        if case .failure(let error) = result, error is CancellationError {
            cancellationWasRequested = true
        }
        lock.unlock()

        pendingTimeoutTask?.cancel()
        pendingContinuation?.resume(with: result)
    }
}

extension SystemExtensionPropertiesRequest: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // Properties requests do not need user approval.
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        complete(with: .success([]))
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        complete(with: .failure(error))
    }

    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        complete(with: .success(properties))
    }
}

@available(macOS 15.1, *)
public final class SystemExtensionActivationStateObserver: NSObject {

    private let extensionBundleID: String
    private let workspace: OSSystemExtensionsWorkspace
    private let onStateChange: () -> Void
    private var isObserving = false

    init(extensionBundleID: String,
         workspace: OSSystemExtensionsWorkspace = .shared,
         onStateChange: @escaping () -> Void) {

        self.extensionBundleID = extensionBundleID
        self.workspace = workspace
        self.onStateChange = onStateChange

        super.init()
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard !isObserving else {
            return
        }

        try workspace.addObserver(self)
        isObserving = true
    }

    public func stop() {
        guard isObserving else {
            return
        }

        workspace.removeObserver(self)
        isObserving = false
    }

    private func handleStateChange(for systemExtensionInfo: OSSystemExtensionInfo) {
        guard systemExtensionInfo.bundleIdentifier == extensionBundleID else {
            return
        }

        onStateChange()
    }
}

@available(macOS 15.1, *)
extension SystemExtensionActivationStateObserver: OSSystemExtensionsWorkspaceObserver {
    public func systemExtensionWillBecomeEnabled(_ systemExtensionInfo: OSSystemExtensionInfo) {
        handleStateChange(for: systemExtensionInfo)
    }

    public func systemExtensionWillBecomeDisabled(_ systemExtensionInfo: OSSystemExtensionInfo) {
        handleStateChange(for: systemExtensionInfo)
    }

    public func systemExtensionWillBecomeInactive(_ systemExtensionInfo: OSSystemExtensionInfo) {
        handleStateChange(for: systemExtensionInfo)
    }
}

final class SystemExtensionRequest: NSObject {

    private let request: OSSystemExtensionRequest
    private let manager: any SystemExtensionRequestManaging
    private let waitingForUserApproval: (() -> Void)?
    private let requestTimeout: TimeInterval
    private(set) var version: String?

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var cancellationWasRequested = false

    private init(request: OSSystemExtensionRequest,
                 manager: any SystemExtensionRequestManaging,
                 waitingForUserApproval: (() -> Void)? = nil,
                 requestTimeout: TimeInterval) {
        self.manager = manager
        self.request = request
        self.waitingForUserApproval = waitingForUserApproval
        self.requestTimeout = requestTimeout

        super.init()
    }

    static func activationRequest(forExtensionWithIdentifier bundleId: String,
                                  manager: any SystemExtensionRequestManaging,
                                  waitingForUserApproval: (() -> Void)?,
                                  requestTimeout: TimeInterval) -> Self {
        self.init(
            request: .activationRequest(forExtensionWithIdentifier: bundleId, queue: .global()),
            manager: manager,
            waitingForUserApproval: waitingForUserApproval,
            requestTimeout: requestTimeout)
    }

    static func deactivationRequest(forExtensionWithIdentifier bundleId: String,
                                    manager: any SystemExtensionRequestManaging,
                                    requestTimeout: TimeInterval) -> Self {
        self.init(
            request: .deactivationRequest(forExtensionWithIdentifier: bundleId, queue: .global()),
            manager: manager,
            requestTimeout: requestTimeout)
    }

    /// Submit the request
    ///
    func submit() async throws {
        try Task.checkCancellation()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                submit(with: continuation)
            }
        } onCancel: {
            complete(with: .failure(CancellationError()))
        }
    }

    private func submit(with continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        assert(self.continuation == nil, "Request can only be submitted once")
        guard !cancellationWasRequested else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }

        self.continuation = continuation
        timeoutTask = makeTimeoutTask()
        lock.unlock()

        request.delegate = self

        guard !Task.isCancelled else {
            complete(with: .failure(CancellationError()))
            return
        }

        manager.submitRequest(request)
    }

    private func makeTimeoutTask() -> Task<Void, Never> {
        let requestTimeout = max(0, requestTimeout)

        return Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(requestTimeout * Double(NSEC_PER_SEC)))
            guard !Task.isCancelled else {
                return
            }

            self?.complete(with: .failure(SystemExtensionRequestError.requestTimedOut))
        }
    }

    private func complete(with result: Result<Void, Error>) {
        lock.lock()
        let pendingContinuation = continuation
        continuation = nil
        let pendingTimeoutTask = timeoutTask
        timeoutTask = nil
        if case .failure(let error) = result, error is CancellationError {
            cancellationWasRequested = true
        }
        lock.unlock()

        pendingTimeoutTask?.cancel()
        pendingContinuation?.resume(with: result)
    }

    private func updateVersion(to version: String) {
        self.version = version
    }

    private func updateVersionNumberIfMissing() {
        guard version == nil,
              let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }

        var extensionVersion = versionString

        if let buildString = Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as? String {
            extensionVersion = extensionVersion + "." + buildString
        }
    }
}

extension SystemExtensionRequest: OSSystemExtensionRequestDelegate {

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {

        updateVersion(to: ext.bundleShortVersion + "." + ext.bundleVersion)
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        waitingForUserApproval?()
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            updateVersionNumberIfMissing()
            complete(with: .success(()))
        case .willCompleteAfterReboot:
            Logger.systemExtensionManager.notice("System extension request will complete after reboot: \(request.identifier, privacy: .public)")
            complete(with: .failure(SystemExtensionRequestError.willActivateAfterReboot))
            return
        @unknown default:
            // Not much we can do about this, so we just let the owning app decide
            // what to do about this.
            Logger.systemExtensionManager.error("System extension request returned unknown result \(result.rawValue, privacy: .public) for \(request.identifier, privacy: .public)")
            complete(with: .failure(SystemExtensionRequestError.unknownRequestResult))
            return
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Self.logRequestFailure(error: error, request: request)
        complete(with: .failure(error))
    }

    private static func logRequestFailure(error: Error, request: OSSystemExtensionRequest) {
        let nsError = error as NSError
        let symbolicName = (error as? OSSystemExtensionError)?.code.symbolicName ?? "n/a"
        Logger.systemExtensionManager.error("""
        System extension request failed
          bundleID:    \(request.identifier, privacy: .public)
          domain:      \(nsError.domain, privacy: .public)
          code:        \(nsError.code, privacy: .public) (\(symbolicName, privacy: .public))
          description: \(error.localizedDescription, privacy: .public)
        """)
    }

}

private extension OSSystemExtensionError.Code {
    var symbolicName: String {
        switch self {
        case .unknown: return "unknown"
        case .missingEntitlement: return "missingEntitlement"
        case .unsupportedParentBundleLocation: return "unsupportedParentBundleLocation"
        case .extensionNotFound: return "extensionNotFound"
        case .extensionMissingIdentifier: return "extensionMissingIdentifier"
        case .duplicateExtensionIdentifer: return "duplicateExtensionIdentifer"
        case .unknownExtensionCategory: return "unknownExtensionCategory"
        case .codeSignatureInvalid: return "codeSignatureInvalid"
        case .validationFailed: return "validationFailed"
        case .forbiddenBySystemPolicy: return "forbiddenBySystemPolicy"
        case .requestCanceled: return "requestCanceled"
        case .requestSuperseded: return "requestSuperseded"
        case .authorizationRequired: return "authorizationRequired"
        @unknown default: return "futureUnknown(\(rawValue))"
        }
    }
}
