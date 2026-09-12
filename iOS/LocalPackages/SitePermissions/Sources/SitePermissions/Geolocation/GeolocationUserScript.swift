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

    private let frameInfo: WKFrameInfo

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

    @MainActor
    public func evaluateJavaScript(_ script: String,
                                   in webView: WKWebView,
                                   completionHandler: @escaping @Sendable (Result<Any, Error>) -> Void) {
        webView.evaluateJavaScript(script, in: frameInfo, in: .page, completionHandler: completionHandler)
    }
}

@MainActor
public protocol GeolocationUserScriptDelegate: AnyObject {

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               getCurrentPositionWith options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame) async -> GeolocationPositionResult

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               constraints: GeolocationRequestConstraints,
                               permissionStateIn frame: GeolocationFrame) -> GeolocationPermissionState

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didStartWatchWithID requestID: String,
                               options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame)

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didCancelWatchWithID requestID: String)
}

public final class GeolocationUserScript: NSObject, UserScript {

    private enum MessageName {
        static let oneShot = "sitePermissionsGeolocation"
        static let watch = "sitePermissionsGeolocationWatch"
    }

    enum MessageKind: String {
        case registerFrame
        case getCurrentPosition
        case queryPermission
        case startWatch
        case clearWatch
    }

    public static var bundle: Bundle { .module }

    static let capabilityToken = UUID().uuidString + UUID().uuidString

    private let installImmediately: Bool

    public lazy var source: String = {
        do {
            return try Self.loadJS("geolocation",
                                   from: Self.bundle,
                                   withReplacements: [
                                    "${CAPABILITY_TOKEN}": Self.capabilityToken,
                                    "${INSTALL_IMMEDIATELY}": String(installImmediately)
                                   ])
        } catch {
            fatalError("Failed to load JS for GeolocationUserScript: \(error.localizedDescription)")
        }
    }()

    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly = false
    public let messageNames = [MessageName.oneShot, MessageName.watch]
    public var requiresRunInPageContentWorld: Bool { true }

    @MainActor public weak var delegate: GeolocationUserScriptDelegate?

    /// Enables the shim for frames owned by the embedding app. The default leaves native APIs untouched.
    @MainActor public var activationHandler: ((GeolocationFrame) -> Bool)?

    @MainActor private var watchRegistry = GeolocationWatchRegistry()
    @MainActor private var frameRegistrations = GeolocationFrameRegistrationStore()

    @MainActor
    /// - Parameter installImmediately: Hardens the page API synchronously at document start. Use only when the
    ///   embedding app scopes this script to its tab web views; exact `duck.ai` origins remain untouched.
    public init(delegate: GeolocationUserScriptDelegate? = nil, installImmediately: Bool = false) {
        self.delegate = delegate
        self.installImmediately = installImmediately
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // All registered message names use the reply-handler overload on iOS 15 and later.
    }

    @MainActor
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              let rawKind = body["kind"] as? String,
              let kind = MessageKind(rawValue: rawKind) else {
            return (Self.errorPayload(.positionUnavailable, message: "Invalid geolocation request"), nil)
        }

        let frame = GeolocationFrame(message.frameInfo)
        guard body["capability"] as? String == Self.capabilityToken else {
            return (Self.errorPayload(.permissionDenied, message: "Unauthenticated geolocation request"), nil)
        }

        if kind == .registerFrame {
            return (handleFrameRegistration(body: body, frame: frame, webView: message.webView), nil)
        }

        guard activationHandler?(frame) == true,
              let nonce = body["nonce"] as? String,
              Self.isValidNonce(nonce),
              let webView = message.webView,
              frame.isAssociated(with: webView),
              let registration = frameRegistrations.registration(
                for: nonce,
                frame: GeolocationNativeFrameIdentity(frame: frame, webView: webView)
              ) else {
            return (Self.errorPayload(.permissionDenied, message: "Unregistered geolocation frame"), nil)
        }

        switch kind {
        case .getCurrentPosition, .queryPermission:
            return (await handleOneShot(kind, body: body, frame: frame, constraints: registration.constraints), nil)
        case .startWatch:
            return (handleWatchStart(body: body,
                                     frame: frame,
                                     nonce: nonce,
                                     constraints: registration.constraints,
                                     webView: webView), nil)
        case .clearWatch:
            return (handleWatchCancellation(body: body, frame: frame, nonce: nonce), nil)
        case .registerFrame:
            return (Self.errorPayload(.positionUnavailable, message: "Invalid geolocation request"), nil)
        }
    }

    /// Cancels all native watches. Call this on navigation and web-content-process replacement.
    @MainActor
    public func cancelAllWatches() {
        let requestIDs = watchRegistry.removeAll()
        frameRegistrations.removeAll()
        for requestID in requestIDs {
            delegate?.geolocationUserScript(self, didCancelWatchWithID: requestID)
        }
    }

    /// Routes an update back to the frame that created the watch.
    ///
    /// Returns `false` after `clearWatch`, navigation, process replacement, or frame teardown.
    @MainActor @discardableResult
    public func send(_ result: GeolocationPositionResult, toWatchWithID requestID: String) -> Bool {
        guard watchRegistry.contains(requestID) else { return false }
        guard let payload = Self.javaScriptObject(from: Self.positionPayload(result)) else { return false }
        let encodedRequestID = Self.javaScriptString(requestID)
        let sent = watchRegistry.send("window.__ddgSitePermissionsGeolocation.receiveWatchResult(\(encodedRequestID), \(payload))",
                                      to: requestID) { [weak self] succeeded in
            guard !succeeded, let self, self.watchRegistry.remove(requestID) else { return }
            self.delegate?.geolocationUserScript(self, didCancelWatchWithID: requestID)
        }
        return sent
    }

    /// Delivers a final result and removes both native and page-side watch state.
    @MainActor @discardableResult
    public func sendTerminal(_ result: GeolocationPositionResult, toWatchWithID requestID: String) -> Bool {
        guard let payload = Self.javaScriptObject(from: Self.positionPayload(result)),
              let callback = watchRegistry.take(requestID) else { return false }

        let encodedRequestID = Self.javaScriptString(requestID)
        callback("window.__ddgSitePermissionsGeolocation.receiveTerminalWatchResult(\(encodedRequestID), \(payload))") { _ in }
        delegate?.geolocationUserScript(self, didCancelWatchWithID: requestID)
        return true
    }

    @MainActor
    func handleOneShot(_ kind: MessageKind,
                       body: [String: Any],
                       frame: GeolocationFrame?,
                       constraints: GeolocationRequestConstraints) async -> [String: Any] {
        guard let delegate, let frame else {
            switch kind {
            case .queryPermission:
                return Self.permissionPayload(.denied)
            case .registerFrame, .getCurrentPosition, .startWatch, .clearWatch:
                return Self.errorPayload(.positionUnavailable, message: "Geolocation is unavailable")
            }
        }

        switch kind {
        case .getCurrentPosition:
            let result = await delegate.geolocationUserScript(self,
                                                               getCurrentPositionWith: Self.options(from: body),
                                                               constraints: constraints,
                                                               in: frame)
            return Self.positionPayload(result)
        case .queryPermission:
            let state = delegate.geolocationUserScript(self,
                                                       constraints: constraints,
                                                       permissionStateIn: frame)
            return Self.permissionPayload(state)
        case .registerFrame, .startWatch, .clearWatch:
            return Self.errorPayload(.positionUnavailable, message: "Invalid one-shot request")
        }
    }

    @MainActor
    private func handleFrameRegistration(body: [String: Any], frame: GeolocationFrame, webView: WKWebView?) -> [String: Any] {
        guard let nonce = body["nonce"] as? String,
              Self.isValidNonce(nonce) else {
            return Self.errorPayload(.permissionDenied, message: "Invalid geolocation frame nonce")
        }
        guard activationHandler?(frame) == true else {
            return ["status": "registered", "enabled": false]
        }
        guard let webView,
              frame.isAssociated(with: webView),
              frameRegistrations.register(nonce: nonce,
                                          frame: GeolocationNativeFrameIdentity(frame: frame, webView: webView),
                                          constraints: Self.constraints(from: body)) else {
            return Self.errorPayload(.permissionDenied, message: "Unable to register geolocation frame")
        }
        return ["status": "registered", "enabled": true]
    }

    @MainActor
    private func handleWatchStart(body: [String: Any],
                                  frame: GeolocationFrame,
                                  nonce: String,
                                  constraints: GeolocationRequestConstraints,
                                  webView: WKWebView?) -> [String: Any] {
        guard let requestID = body["requestID"] as? String,
              Self.isValidRequestID(requestID),
              let webView,
              let delegate else {
            return Self.errorPayload(.positionUnavailable, message: "Geolocation is unavailable")
        }

        let registered = watchRegistry.register(requestID,
                                                nonce: nonce) { [weak webView] script, completion in
            guard let webView else {
                completion(false)
                return
            }
            frame.evaluateJavaScript(script, in: webView) { result in
                completion((try? result.get()) != nil)
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
    private func handleWatchCancellation(body: [String: Any], frame: GeolocationFrame, nonce: String) -> [String: Any] {
        guard let requestID = body["requestID"] as? String,
              Self.isValidRequestID(requestID) else {
            return Self.errorPayload(.positionUnavailable, message: "Invalid geolocation watch")
        }

        if watchRegistry.remove(requestID, nonce: nonce) {
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

@available(iOS 14.0, *)
extension GeolocationUserScript: WKScriptMessageHandlerWithReply {}

@MainActor
final class GeolocationWatchRegistry {

    typealias Callback = (String, @escaping (Bool) -> Void) -> Void

    private struct Entry {
        let nonce: String
        let callback: Callback
    }

    private var entries = [String: Entry]()

    var count: Int { entries.count }

    func contains(_ requestID: String) -> Bool {
        entries[requestID] != nil
    }

    func register(_ requestID: String,
                  nonce: String,
                  callback: @escaping Callback) -> Bool {
        guard entries[requestID] == nil else { return false }
        entries[requestID] = Entry(nonce: nonce, callback: callback)
        return true
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
    func remove(_ requestID: String, nonce: String) -> Bool {
        guard let entry = entries[requestID],
              entry.nonce == nonce else { return false }
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

@MainActor
final class GeolocationFrameRegistrationStore {

    struct Registration: Equatable {
        let nonce: String
        let frame: GeolocationNativeFrameIdentity
        let constraints: GeolocationRequestConstraints
    }

    private var registrations = [String: Registration]()

    var count: Int { registrations.count }

    func register(nonce: String,
                  frame: GeolocationNativeFrameIdentity,
                  constraints: GeolocationRequestConstraints) -> Bool {
        if let registration = registrations[nonce] {
            return registration.frame == frame
        }
        registrations[nonce] = Registration(nonce: nonce, frame: frame, constraints: constraints)
        return true
    }

    func registration(for nonce: String, frame: GeolocationNativeFrameIdentity) -> Registration? {
        guard let registration = registrations[nonce], registration.frame == frame else { return nil }
        return registration
    }

    func removeAll() {
        registrations.removeAll()
    }
}

struct GeolocationNativeFrameIdentity: Equatable {

    let webViewID: ObjectIdentifier
    let scheme: String
    let host: String
    let port: Int
    let isMainFrame: Bool

    init(webViewID: ObjectIdentifier,
         scheme: String,
         host: String,
         port: Int,
         isMainFrame: Bool) {
        self.webViewID = webViewID
        self.scheme = scheme
        self.host = host
        self.port = port
        self.isMainFrame = isMainFrame
    }

    init(frame: GeolocationFrame, webView: WKWebView) {
        webViewID = ObjectIdentifier(webView)
        scheme = frame.securityOrigin.protocol
        host = frame.securityOrigin.host
        port = frame.securityOrigin.port
        isMainFrame = frame.isMainFrame
    }
}
