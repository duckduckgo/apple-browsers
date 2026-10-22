//
//  GeolocationUserScript.swift
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
import UserScript
import WebKit

/// Native options use seconds; the bridge converts JavaScript's millisecond values.
public struct GeolocationRequestOptions: Equatable, Sendable {

    public let enableHighAccuracy: Bool
    public let timeout: TimeInterval?
    public let maximumAge: TimeInterval

    public init(enableHighAccuracy: Bool = false,
                timeout: TimeInterval? = nil,
                maximumAge: TimeInterval = 0) {
        self.enableHighAccuracy = enableHighAccuracy
        self.timeout = timeout
        self.maximumAge = maximumAge
    }
}

/// Frame preflight checks, not a grant. The delegate still checks effective permissions.
public struct GeolocationRequestConstraints: Equatable, Sendable {

    public let isSecureContext: Bool
    public let isSandboxed: Bool
    public let isPolicyAllowed: Bool

    public init(isSecureContext: Bool, isSandboxed: Bool, isPolicyAllowed: Bool) {
        self.isSecureContext = isSecureContext
        self.isSandboxed = isSandboxed
        self.isPolicyAllowed = isPolicyAllowed
    }

    public var allowsRequest: Bool {
        isSecureContext && !isSandboxed && isPolicyAllowed
    }
}

public struct GeolocationPosition: Equatable, Sendable {

    public struct Coordinates: Equatable, Sendable {
        public let latitude: Double
        public let longitude: Double
        public let accuracy: Double
        public let altitude: Double?
        public let altitudeAccuracy: Double?
        public let heading: Double?
        public let speed: Double?
    }

    public let coordinates: Coordinates
    public let timestamp: Date

    public init(location: CLLocation) {
        let coordinate = location.coordinate
        coordinates = Coordinates(latitude: coordinate.latitude,
                                  longitude: coordinate.longitude,
                                  accuracy: location.horizontalAccuracy,
                                  altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                                  altitudeAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
                                  heading: location.course >= 0 ? location.course : nil,
                                  speed: location.speed >= 0 ? location.speed : nil)
        timestamp = location.timestamp
    }

    public init(coordinates: Coordinates, timestamp: Date) {
        self.coordinates = coordinates
        self.timestamp = timestamp
    }
}

public struct GeolocationPositionError: Error, Equatable, Sendable {

    public enum Code: Int, Sendable {
        case permissionDenied = 1
        case positionUnavailable = 2
        case timeout = 3
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

public typealias GeolocationPositionResult = Result<GeolocationPosition, GeolocationPositionError>
public typealias GeolocationPermissionState = SitePermissionQueryState

/// A page frame that can receive callbacks without exposing its `WKFrameInfo`.
///
/// Reading `WKFrameInfo.request` terminates the app. Callers receive only safe, native-derived
/// attribution fields and the ability to evaluate a callback in the exact requesting frame.
public struct GeolocationFrame {

    fileprivate let frameInfo: WKFrameInfo

    public let securityOrigin: WKSecurityOrigin
    public let isMainFrame: Bool
    public let requestingFrameID: UInt64

    init(_ frameInfo: WKFrameInfo) {
        self.frameInfo = frameInfo
        securityOrigin = frameInfo.securityOrigin
        isMainFrame = frameInfo.isMainFrame
        requestingFrameID = UInt64(UInt(bitPattern: ObjectIdentifier(frameInfo)))
    }

    public func isAssociated(with webView: WKWebView) -> Bool {
        frameInfo.webView === webView
    }

    /// Evaluates `script` in this frame's isolated content world, where the content-scope policy feature runs.
    @MainActor
    public func evaluateJavaScript(_ script: String,
                                   in webView: WKWebView,
                                   completionHandler: @escaping @Sendable (Result<Any, Error>) -> Void) {
        webView.evaluateJavaScript(script, in: frameInfo, in: .defaultClient, completionHandler: completionHandler)
    }
}

/// Enforces native permission and lifecycle checks after the script's frame preflight.
/// The embedding app must also enforce the committed main-frame response's Permissions-Policy;
/// JavaScript cannot inspect response headers when WebKit lacks its policy API.
@MainActor
public protocol GeolocationUserScriptDelegate: AnyObject {

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               getCurrentPositionWith options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame) async -> GeolocationPositionResult

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               permissionStatusID: String,
                               constraints: GeolocationRequestConstraints,
                               permissionStateIn frame: GeolocationFrame) -> GeolocationPermissionState

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didStartWatchWithID requestID: String,
                               options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame)

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didCancelWatchWithID requestID: String)

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didCancelPermissionStatusWithID statusID: String)
}

/// Routes page requests from the `sitePermissionsGeolocation` content-scope feature after checking
/// policy in the isolated content world. Register it with the page-world `ContentScopeUserScript`, and
/// inject `featureSettings` and `policyFeatureSettings` into the page-world and isolated configurations.
/// The delegate owns site and system permissions, location acquisition, and cancellation of its pending work.
public final class GeolocationUserScript: NSObject, Subfeature {

    /// The page-world content-scope feature this subfeature serves.
    public static let featureNameValue = "sitePermissionsGeolocation"
    /// The isolated-world content-scope feature that evaluates frame policy.
    public static let policyFeatureName = "sitePermissionsGeolocationPolicy"

    enum MessageKind: String {
        case getCurrentPosition
        case queryPermission
        case startWatch
        case clearWatch
    }

    enum Subscription: String {
        case watchResult = "geolocationWatchResult"
        case terminalWatchResult = "geolocationTerminalWatchResult"
        case permissionState = "geolocationPermissionState"
    }

    static let capabilityToken = UUID().uuidString + UUID().uuidString
    /// The isolated content-scope script's messaging context, which its subscriptions require.
    private static let isolatedMessagingContext = "contentScopeScriptsIsolated"

    /// Asks the isolated-world policy feature for the frame's current constraints and awaits its reply.
    private static let policyConstraintsScript: String = {
        let subscriptionName = "geolocationPolicyConstraints"
        let event: [String: Any] = [
            "context": isolatedMessagingContext,
            "featureName": policyFeatureName,
            "subscriptionName": subscriptionName,
            "params": [String: Any]()
        ]
        let encodedEvent = javaScriptObject(from: event) ?? "{}"
        return "return await navigator.duckduckgo?.messageHandlers?.[\(javaScriptString(subscriptionName))]?.(\(encodedEvent));"
    }()

    public let featureName = GeolocationUserScript.featureNameValue
    public let messageOriginPolicy: MessageOriginPolicy = .all
    public weak var broker: UserScriptMessageBroker?

    /// Settings for the page-world feature. Without them the feature leaves the page untouched.
    /// With them it hardens the page API at document start, so inject them only into tab web views;
    /// `duck.ai` and its subdomains remain untouched.
    public var featureSettings: [String: Any] {
        ["capability": Self.capabilityToken]
    }

    /// Settings for the isolated-world policy feature. Without them it does not run.
    public static var policyFeatureSettings: [String: Any] {
        ["enabled": true]
    }

    @MainActor public weak var delegate: GeolocationUserScriptDelegate?

    /// Decides which frames native code serves. Requests from other frames, and every request without it, are denied.
    @MainActor public var activationHandler: ((GeolocationFrame) -> Bool)?

    @MainActor private var watchRegistry = GeolocationWatchRegistry()
    @MainActor private var permissionStatusRegistry = GeolocationWatchRegistry()
    @MainActor private var lifecycleGeneration: UInt64 = 0
    @MainActor private var pendingDocumentEvaluations = [UUID: CheckedContinuation<Any?, Never>]()

    @MainActor
    public init(delegate: GeolocationUserScriptDelegate? = nil) {
        self.delegate = delegate
        super.init()
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let kind = MessageKind(rawValue: methodName) else { return nil }
        return { [weak self] params, message in
            guard let self else { return nil }
            let body = params as? [String: Any] ?? [:]
            return await SitePermissionsBridgeReply(self.handle(kind, body: body, message: message))
        }
    }

    @MainActor
    func handle(_ kind: MessageKind, body: [String: Any], message: WKScriptMessage) async -> [String: Any] {
        let frame = GeolocationFrame(message.frameInfo)
        guard body["capability"] as? String == Self.capabilityToken else {
            return Self.errorPayload(.permissionDenied, message: "Unauthenticated geolocation request")
        }

        // Each request names its page document. Only the isolated world can prove that the frame still
        // holds that document, so its report also supplies the policy and sandbox verdict for the request.
        guard activationHandler?(frame) == true,
              let pageDocumentID = body["documentID"] as? String,
              Self.isValidNonce(pageDocumentID),
              let webView = message.webView,
              frame.isAssociated(with: webView) else {
            return Self.errorPayload(.permissionDenied, message: "Geolocation is not active in this frame")
        }

        let generation = lifecycleGeneration
        guard let policy = await documentPolicy(in: frame, webView: webView, generation: generation),
              policy.pageDocumentID == pageDocumentID,
              generation == lifecycleGeneration,
              activationHandler?(frame) == true,
              frame.isAssociated(with: webView) else {
            return Self.errorPayload(.permissionDenied, message: "Geolocation document is no longer active")
        }
        guard kind == .clearWatch || policy.constraints.allowsRequest else {
            if kind == .queryPermission {
                return Self.permissionPayload(.denied)
            }
            return Self.errorPayload(.permissionDenied, message: "Geolocation is not allowed in this context")
        }

        switch kind {
        case .getCurrentPosition:
            return await handlePositionRequest(body: body, frame: frame, constraints: policy.constraints)
        case .queryPermission:
            return handlePermissionQuery(body: body,
                                         frame: frame,
                                         pageDocumentID: pageDocumentID,
                                         documentID: policy.documentID,
                                         constraints: policy.constraints,
                                         webView: webView)
        case .startWatch:
            return handleWatchStart(body: body,
                                    frame: frame,
                                    pageDocumentID: pageDocumentID,
                                    documentID: policy.documentID,
                                    constraints: policy.constraints,
                                    webView: webView)
        case .clearWatch:
            return handleWatchCancellation(body: body, pageDocumentID: pageDocumentID)
        }
    }

    /// Cancels watches and permission-status subscriptions, and resolves pending document checks
    /// with no result.
    /// Call on navigation, process replacement, and tab teardown. The delegate must
    /// separately cancel pending one-shot work.
    @MainActor
    public func cancelAllWatches() {
        lifecycleGeneration &+= 1
        let evaluations = pendingDocumentEvaluations
        pendingDocumentEvaluations.removeAll()
        evaluations.values.forEach { $0.resume(returning: nil) }
        let requestIDs = watchRegistry.removeAll()
        let statusIDs = permissionStatusRegistry.removeAll()
        for requestID in requestIDs {
            delegate?.geolocationUserScript(self, didCancelWatchWithID: requestID)
        }
        for statusID in statusIDs {
            delegate?.geolocationUserScript(self, didCancelPermissionStatusWithID: statusID)
        }
    }

    /// Routes an update back to the frame that created the watch.
    ///
    /// Returns whether delivery was scheduled. A later negative acknowledgement removes
    /// the watch and asks the delegate to cancel location acquisition.
    @MainActor @discardableResult
    public func send(_ result: GeolocationPositionResult, toWatchWithID requestID: String) -> Bool {
        guard let documentID = watchRegistry.documentID(for: requestID),
              let script = callbackScript(.watchResult,
                                          documentID: documentID,
                                          params: ["requestID": requestID, "result": Self.positionPayload(result)]) else { return false }
        let sent = watchRegistry.send(script, to: requestID) { [weak self] succeeded in
            guard !succeeded, let self, self.watchRegistry.remove(requestID) else { return }
            self.delegate?.geolocationUserScript(self, didCancelWatchWithID: requestID)
        }
        return sent
    }

    /// Delivers a final result and removes both native and page-side watch state.
    @MainActor @discardableResult
    public func sendTerminal(_ result: GeolocationPositionResult, toWatchWithID requestID: String) -> Bool {
        guard let documentID = watchRegistry.documentID(for: requestID),
              let script = callbackScript(.terminalWatchResult,
                                          documentID: documentID,
                                          params: ["requestID": requestID, "result": Self.positionPayload(result)]),
              let callback = watchRegistry.take(requestID) else { return false }

        callback(script) { _ in }
        delegate?.geolocationUserScript(self, didCancelWatchWithID: requestID)
        return true
    }

    /// Refreshes a previously queried `PermissionStatus` in its exact requesting frame.
    @MainActor @discardableResult
    public func send(_ state: GeolocationPermissionState, toPermissionStatusWithID statusID: String) -> Bool {
        guard let documentID = permissionStatusRegistry.documentID(for: statusID),
              let script = callbackScript(.permissionState,
                                          documentID: documentID,
                                          params: ["statusID": statusID, "state": state.rawValue]) else { return false }
        return permissionStatusRegistry.send(script, to: statusID) { [weak self] succeeded in
            guard !succeeded, let self, self.permissionStatusRegistry.remove(statusID) else { return }
            self.delegate?.geolocationUserScript(self, didCancelPermissionStatusWithID: statusID)
        }
    }

    @MainActor
    private func handlePositionRequest(body: [String: Any],
                                       frame: GeolocationFrame,
                                       constraints: GeolocationRequestConstraints) async -> [String: Any] {
        guard let delegate else {
            return Self.errorPayload(.positionUnavailable, message: "Geolocation is unavailable")
        }

        let result = await delegate.geolocationUserScript(self,
                                                           getCurrentPositionWith: Self.options(from: body),
                                                           constraints: constraints,
                                                           in: frame)
        return Self.positionPayload(result)
    }

    @MainActor
    private func handlePermissionQuery(body: [String: Any],
                                       frame: GeolocationFrame,
                                       pageDocumentID: String,
                                       documentID: String,
                                       constraints: GeolocationRequestConstraints,
                                       webView: WKWebView) -> [String: Any] {
        guard let statusID = body["statusID"] as? String,
              Self.isCallbackID(statusID, ownedBy: pageDocumentID),
              let delegate else {
            return Self.permissionPayload(.denied)
        }

        let registered = permissionStatusRegistry.register(statusID,
                                                           owner: pageDocumentID,
                                                           documentID: documentID) { [weak webView] script, completion in
            guard let webView else {
                completion(false)
                return
            }
            frame.evaluateJavaScript(script, in: webView) { result in
                completion((try? result.get()) as? Bool == true)
            }
        }
        guard registered else {
            return Self.errorPayload(.positionUnavailable, message: "Duplicate geolocation permission status")
        }

        let state = delegate.geolocationUserScript(self,
                                                   permissionStatusID: statusID,
                                                   constraints: constraints,
                                                   permissionStateIn: frame)
        return Self.permissionPayload(state)
    }

    @MainActor
    private func documentPolicy(in frame: GeolocationFrame,
                                webView: WKWebView,
                                generation: UInt64) async -> GeolocationDocumentPolicy? {
        let value = await evaluateDocumentJavaScript(generation: generation) { completion in
            webView.callAsyncJavaScript(
                Self.policyConstraintsScript,
                arguments: [:], in: frame.frameInfo, in: .defaultClient, completionHandler: completion)
        }
        guard let value,
              let policy = value as? [String: Any],
              let documentID = policy["documentID"] as? String,
              Self.isValidNonce(documentID) else { return nil }
        // The isolated world reports the page feature's identity in the same reply, so both belong to one document.
        let pageDocumentID = policy["pageDocumentID"] as? String
        return GeolocationDocumentPolicy(documentID: documentID,
                                         pageDocumentID: pageDocumentID.flatMap { Self.isValidNonce($0) ? $0 : nil },
                                         constraints: Self.constraints(from: policy))
    }

    @MainActor
    private func evaluateDocumentJavaScript(
        generation: UInt64,
        _ evaluate: (@escaping @MainActor @Sendable (Result<Any, Error>) -> Void) -> Void
    ) async -> Any? {
        // Teardown only resolves waits that already exist, so a stale caller must not start a new one.
        guard generation == lifecycleGeneration else { return nil }
        let evaluationID = UUID()
        return await withCheckedContinuation { continuation in
            pendingDocumentEvaluations[evaluationID] = continuation
            // WebKit may never finish an evaluation in a retired document. Page teardown resolves
            // the wait; removing its entry also makes a late WebKit completion harmless.
            evaluate { [weak self] result in
                self?.pendingDocumentEvaluations.removeValue(forKey: evaluationID)?.resume(returning: try? result.get())
            }
        }
    }

    @MainActor
    private func handleWatchStart(body: [String: Any],
                                  frame: GeolocationFrame,
                                  pageDocumentID: String,
                                  documentID: String,
                                  constraints: GeolocationRequestConstraints,
                                  webView: WKWebView?) -> [String: Any] {
        guard let requestID = body["requestID"] as? String,
              Self.isCallbackID(requestID, ownedBy: pageDocumentID),
              let webView,
              let delegate else {
            return Self.errorPayload(.positionUnavailable, message: "Geolocation is unavailable")
        }

        // Register before invoking the delegate, which may send an update immediately.
        let registered = watchRegistry.register(requestID,
                                                owner: pageDocumentID,
                                                documentID: documentID) { [weak webView] script, completion in
            guard let webView else {
                completion(false)
                return
            }
            frame.evaluateJavaScript(script, in: webView) { result in
                completion((try? result.get()) as? Bool == true)
            }
        }
        guard registered else {
            return Self.errorPayload(.positionUnavailable, message: "Duplicate geolocation watch")
        }

        delegate.geolocationUserScript(self,
                                       didStartWatchWithID: requestID,
                                       options: Self.options(from: body),
                                       constraints: constraints,
                                       in: frame)
        return ["status": "started"]
    }

    @MainActor
    private func handleWatchCancellation(body: [String: Any], pageDocumentID: String) -> [String: Any] {
        guard let requestID = body["requestID"] as? String,
              Self.isCallbackID(requestID, ownedBy: pageDocumentID) else {
            return Self.errorPayload(.positionUnavailable, message: "Invalid geolocation watch")
        }

        if watchRegistry.remove(requestID, owner: pageDocumentID) {
            delegate?.geolocationUserScript(self, didCancelWatchWithID: requestID)
        }
        return ["status": "cleared"]
    }

    static func options(from body: [String: Any]) -> GeolocationRequestOptions {
        guard let values = body["options"] as? [String: Any] else { return .init() }

        func nonnegativeFiniteNumber(named key: String) -> Double? {
            guard let value = values[key] as? NSNumber else { return nil }
            let number = value.doubleValue
            return number.isFinite && number >= 0 ? number : nil
        }

        let maximumAge: TimeInterval
        if values["maximumAge"] as? String == "infinity" {
            maximumAge = .infinity
        } else {
            maximumAge = (nonnegativeFiniteNumber(named: "maximumAge") ?? 0) / 1_000
        }

        return GeolocationRequestOptions(enableHighAccuracy: values["enableHighAccuracy"] as? Bool ?? false,
                                         timeout: nonnegativeFiniteNumber(named: "timeout").map { $0 / 1_000 },
                                         maximumAge: maximumAge)
    }

    static func constraints(from body: [String: Any]) -> GeolocationRequestConstraints {
        GeolocationRequestConstraints(isSecureContext: body["isSecureContext"] as? Bool ?? false,
                                      isSandboxed: body["isSandboxed"] as? Bool ?? true,
                                      isPolicyAllowed: body["isPolicyAllowed"] as? Bool ?? false)
    }

    static func isValidNonce(_ nonce: String) -> Bool {
        let bytes = nonce.utf8
        return bytes.count == 32 && bytes.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    /// Whether `callbackID` is a valid watch or permission-status ID that the page document created.
    static func isCallbackID(_ callbackID: String, ownedBy pageDocumentID: String) -> Bool {
        isValidRequestID(callbackID) && callbackID.hasPrefix(pageDocumentID + ":")
    }

    static func isValidRequestID(_ requestID: String) -> Bool {
        guard requestID.utf8.count <= 128 else { return false }
        let components = requestID.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              isValidNonce(String(components[0])),
              let watchID = UInt64(components[1]),
              watchID > 0 else { return false }
        return true
    }

    static func positionPayload(_ result: GeolocationPositionResult) -> [String: Any] {
        switch result {
        case .success(let position):
            let coordinates = position.coordinates
            let coordinatePayload: [String: Any] = [
                "latitude": coordinates.latitude,
                "longitude": coordinates.longitude,
                "accuracy": coordinates.accuracy,
                "altitude": jsonValue(coordinates.altitude),
                "altitudeAccuracy": jsonValue(coordinates.altitudeAccuracy),
                "heading": jsonValue(coordinates.heading),
                "speed": jsonValue(coordinates.speed)
            ]
            return [
                "status": "success",
                "coords": coordinatePayload,
                "timestamp": position.timestamp.timeIntervalSince1970 * 1_000
            ]
        case .failure(let error):
            return errorPayload(error.code, message: error.message)
        }
    }

    static func permissionPayload(_ state: GeolocationPermissionState) -> [String: Any] {
        ["status": "permission", "state": state.rawValue]
    }

    static func errorPayload(_ code: GeolocationPositionError.Code, message: String) -> [String: Any] {
        ["status": "error", "code": code.rawValue, "message": message]
    }

    private static func javaScriptObject(from payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// Builds a delivery for the isolated policy feature, which forwards it to the page feature only while
    /// the frame still holds the document with `documentID`: a WKFrameInfo can outlive its document.
    /// The script evaluates to `true` when the page feature acknowledges ownership.
    private func callbackScript(_ subscription: Subscription, documentID: String, params: [String: Any]) -> String? {
        let deliverySubscription = "geolocationDeliver"
        let event: [String: Any] = [
            "context": Self.isolatedMessagingContext,
            "featureName": Self.policyFeatureName,
            "subscriptionName": deliverySubscription,
            "params": [
                "documentID": documentID,
                "subscriptionName": subscription.rawValue,
                "params": params
            ]
        ]
        guard let encodedEvent = Self.javaScriptObject(from: event) else { return nil }
        return "navigator.duckduckgo?.messageHandlers?.[\(Self.javaScriptString(deliverySubscription))]?.(\(encodedEvent)) === true"
    }

    private static func jsonValue(_ value: Double?) -> Any {
        if let value {
            return value
        }
        return NSNull()
    }

    private static func javaScriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              var encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        encoded.removeFirst()
        encoded.removeLast()
        return encoded
    }
}

@MainActor
final class GeolocationWatchRegistry {

    typealias Callback = (String, @escaping (Bool) -> Void) -> Void

    private struct Entry {
        /// The page document that created the callback.
        let owner: String
        let documentID: String
        let callback: Callback
    }

    private var entries = [String: Entry]()

    var count: Int { entries.count }

    func contains(_ requestID: String) -> Bool {
        entries[requestID] != nil
    }

    /// - Parameter documentID: The isolated-world identity of the document that owns `requestID`.
    func register(_ requestID: String,
                  owner: String,
                  documentID: String,
                  callback: @escaping Callback) -> Bool {
        guard entries[requestID] == nil else { return false }
        entries[requestID] = Entry(owner: owner, documentID: documentID, callback: callback)
        return true
    }

    func documentID(for requestID: String) -> String? {
        entries[requestID]?.documentID
    }

    func send(_ script: String,
              to requestID: String,
              completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard let entry = entries[requestID] else { return false }
        entry.callback(script, completion)
        return true
    }

    @discardableResult
    func remove(_ requestID: String) -> Bool {
        entries.removeValue(forKey: requestID) != nil
    }

    @discardableResult
    func remove(_ requestID: String, owner: String) -> Bool {
        guard let entry = entries[requestID],
              entry.owner == owner else { return false }
        entries.removeValue(forKey: requestID)
        return true
    }

    func removeAll() -> [String] {
        defer { entries.removeAll() }
        return Array(entries.keys)
    }

    func take(_ requestID: String) -> Callback? {
        entries.removeValue(forKey: requestID)?.callback
    }
}

/// A frame's policy as the isolated world reported it, with both worlds' identities for its current document.
struct GeolocationDocumentPolicy {

    let documentID: String
    let pageDocumentID: String?
    let constraints: GeolocationRequestConstraints
}
