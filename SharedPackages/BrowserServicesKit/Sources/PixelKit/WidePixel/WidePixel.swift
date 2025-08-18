//
//  WidePixel.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import os.log
import Common

#if os(iOS)
import UIKit
#endif

public protocol WidePixelManaging {
    func startFlow<T: WidePixelData>(_ data: T)
    func updateFlow<T: WidePixelData>(_ data: T)
    func completeFlow<T: WidePixelData>(_ data: T, finalStatus: WidePixelFinalStatus, onComplete: @escaping PixelKit.CompletionBlock)

    func startMeasuring<T: WidePixelData>(_ data: inout T, keyPath: WritableKeyPath<T, MeasuredInterval?>)
    func stopMeasuring<T: WidePixelData>(_ data: inout T, keyPath: WritableKeyPath<T, MeasuredInterval?>)

    func getAllFlowData<T: WidePixelData>(_ type: T.Type) -> [T]
    func getFlowData<T: WidePixelData>(_ type: T.Type, contextID: UUID) -> T?

    func getActiveFlowNames() -> [String]
    func clearAllFlows()
}

// MARK: - WidePixelManaging convenience defaults

public extension WidePixelManaging {
    func completeFlow<T: WidePixelData>(_ data: T, onComplete: @escaping PixelKit.CompletionBlock = { _, _ in }) {
        completeFlow(data, finalStatus: .success, onComplete: onComplete)
    }
}

public final class WidePixel: WidePixelManaging {

    // MARK: - Storage Configuration

    public static let storageKeyPrefix = "com.duckduckgo.wide-pixel.storage"
    private static let logger = Logger(subsystem: "PixelKit", category: "Wide Pixel")
    private static let storageQueue = DispatchQueue(label: "com.duckduckgo.wide-pixel.storage-queue", qos: .utility)

    private let defaults: UserDefaults
    private let storage: WidePixelStoring
    private let pixelKitProvider: () -> PixelKit?
    private let sampler: WidePixelSampling
    private let eventMapping: EventMapping<WidePixelEvents>?

    public init(userDefaults: UserDefaults = UserDefaults(suiteName: WidePixel.storageKeyPrefix) ?? .standard,
                pixelKitProvider: @escaping () -> PixelKit? = { PixelKit.shared },
                sampler: WidePixelSampling = DefaultWidePixelSampler(),
                storage: WidePixelStoring? = nil,
                events: EventMapping<WidePixelEvents>? = nil) {
        self.defaults = userDefaults
        self.pixelKitProvider = pixelKitProvider
        self.sampler = sampler
        self.storage = storage ?? WidePixelUserDefaultsStorage(userDefaults: userDefaults)
        self.eventMapping = events
    }

    // MARK: - Public API

    public func startFlow<T: WidePixelData>(_ data: T) {
        Self.logger.info("Starting wide pixel flow: \(T.pixelName, privacy: .public) with context ID: \(data.contextData.id, privacy: .public)")
        do {
            try Self.storageQueue.sync { try storage.save(data) }
        } catch {
            report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
        }
    }

    // removed: updateFlowParameters; callers should mutate their instance and call updateFlow(_:) instead

    public func updateFlow<T: WidePixelData>(_ data: T) {
        let contextID = data.contextData.id
        do {
            try Self.storageQueue.sync { try storage.update(data) }
        } catch {
            report(.updateFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
            return
        }

        Self.logger.debug("Wide pixel flow updated: \(T.pixelName, privacy: .public) with context ID: \(contextID, privacy: .public)")
    }

    public func getFlowData<T: WidePixelData>(_ type: T.Type, contextID: UUID) -> T? {
        return Self.storageQueue.sync { try? storage.load(contextID: contextID) }
    }

    public func getAllFlowData<T: WidePixelData>(_ type: T.Type) -> [T] {
        return Self.storageQueue.sync { storage.allFlowData(for: T.self) }
    }

    // MARK: - Flow Completion

    public func completeFlow<T: WidePixelData>(_ data: T, finalStatus: WidePixelFinalStatus, onComplete: @escaping PixelKit.CompletionBlock = { _, _ in }) {
        Self.logger.info("Completing wide pixel flow: \(T.pixelName, privacy: .public) with context ID: \(data.contextData.id, privacy: .public)")

        do {
            try storage.update(data)
            let current: T = try storage.load(contextID: data.contextData.id)
            guard shouldSampleFlow(current) else {
                handleDroppedFlow(for: data.contextData.id, sampleRate: current.globalData.sampleRate)
                onComplete(true, nil)
                return
            }

            let parameters = try generateFinalParameters(from: current, expectedType: T.self, withStatus: finalStatus)

            clearFlow(for: data.contextData.id)
            try firePixel(named: T.pixelName, parameters: parameters, onComplete: onComplete)
            Self.logger.info("Completed wide pixel flow: \(T.pixelName, privacy: .public) with context ID: \(data.contextData.id, privacy: .public)")
        } catch {
            Self.logger.error("Failed to complete wide pixel flow \(T.pixelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            report(.completeFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
            clearFlow(for: data.contextData.id)
            onComplete(false, error)
        }
    }

    private func shouldSampleFlow(_ data: any WidePixelData) -> Bool {
        return sampler.shouldSend(sampleRate: data.globalData.sampleRate)
    }

    private func handleDroppedFlow(for contextID: UUID, sampleRate: Double) {
        clearFlow(for: contextID)
        Self.logger.info("Wide pixel dropped due to sample rate (\(sampleRate, privacy: .public)) for context ID: \(contextID, privacy: .public)")
    }

    private func generateFinalParameters<T: WidePixelData>(from typed: T, expectedType: T.Type, withStatus status: WidePixelFinalStatus) throws -> [String: String] {
        var parameters: [String: String] = [:]
        parameters.merge(typed.globalData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(typed.appData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(typed.contextData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(typed.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters["feature.name"] = T.pixelName
        parameters["feature.status"] = status.asString
        if case let .unknown(reason) = status, !reason.isEmpty {
            parameters["feature.status.unknown-status-reason"] = reason
        }
        return parameters
    }

    private func firePixel(
        named pixelName: String,
        parameters: [String: String],
        onComplete: @escaping PixelKit.CompletionBlock
    ) throws {
        guard !pixelName.isEmpty else {
            Self.logger.error("Cannot fire wide pixel: empty pixel name")
            onComplete(false, WidePixelError.invalidParameters("Pixel name cannot be empty"))
            return
        }

        guard !parameters.isEmpty else {
            Self.logger.warning("Cannot fire wide pixel: empty parameters \(pixelName, privacy: .public)")
            onComplete(false, WidePixelError.invalidParameters("Parameters should not be empty"))
            return
        }

        guard let pixelKit = pixelKitProvider() else {
            Self.logger.error("Cannot fire wide pixel: PixelKit not initialized")
            onComplete(false, WidePixelError.invalidFlowState)
            return
        }

        let finalPixelName = Self.generatePixelName(for: pixelName)
        let widePixelEvent = WidePixelEvent(name: finalPixelName, parameters: parameters)

        pixelKit.fire(
            widePixelEvent,
            frequency: .standard,
            withHeaders: nil,
            withAdditionalParameters: nil,
            withError: nil,
            allowedQueryReservedCharacters: nil,
            includeAppVersionParameter: false,
            onComplete: { success, error in
                if success {
                    Self.logger.info("Wide pixel fired successfully: \(finalPixelName, privacy: .public)")
                } else {
                    Self.logger.error("Wide pixel failed to fire: \(finalPixelName, privacy: .public), error: \(String(describing: error), privacy: .public)")
                }

                onComplete(success, error)
            }
        )
    }

    public func completeFlow<T: WidePixelData>(
        _ type: T.Type, contextID: UUID,
        finalStatus: WidePixelFinalStatus,
        onComplete: @escaping PixelKit.CompletionBlock = { _, _ in }
    ) {
        guard let currentData = getFlowData(T.self, contextID: contextID) else {
            report(.loadFailed(pixelName: T.pixelName, error: WidePixelError.flowNotFound(pixelName: T.pixelName)), error: WidePixelError.flowNotFound(pixelName: T.pixelName), params: nil)
            onComplete(false, WidePixelError.flowNotFound(pixelName: T.pixelName))
            return
        }
        completeFlow(currentData, finalStatus: finalStatus, onComplete: onComplete)
    }

    // MARK: - Duration Measurements

    public func startMeasuring<T: WidePixelData>(_ type: T.Type, contextID: UUID, keyPath: WritableKeyPath<T, MeasuredInterval?>) {
        guard var typed: T = try? storage.load(contextID: contextID) else {
            report(.loadFailed(pixelName: T.pixelName, error: WidePixelError.flowNotFound(pixelName: T.pixelName)), error: WidePixelError.flowNotFound(pixelName: T.pixelName), params: nil)
            return
        }
        var interval = typed[keyPath: keyPath] ?? MeasuredInterval()
        if interval.start != nil { assertionFailure("startMeasuring called but start is already set"); return }
        interval.start = Date()
        typed[keyPath: keyPath] = interval
        do { try Self.storageQueue.sync { try storage.save(typed) } } catch { report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil) }
    }

    public func stopMeasuring<T: WidePixelData>(_ type: T.Type, contextID: UUID, keyPath: WritableKeyPath<T, MeasuredInterval?>) {
        guard var typed: T = try? storage.load(contextID: contextID) else {
            report(.loadFailed(pixelName: T.pixelName, error: WidePixelError.flowNotFound(pixelName: T.pixelName)), error: WidePixelError.flowNotFound(pixelName: T.pixelName), params: nil)
            return
        }
        var interval = typed[keyPath: keyPath] ?? MeasuredInterval()
        let now = Date()
        if interval.start == nil { interval.start = now }
        interval.end = now
        typed[keyPath: keyPath] = interval
        do { try Self.storageQueue.sync { try storage.save(typed) } } catch { report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil) }
    }

    // MARK: - Test Helpers

    func startMeasuring<T: WidePixelData>(_ type: T.Type, contextID: UUID, keyPath: WritableKeyPath<T, MeasuredInterval?>, at date: Date) {
        guard var typed: T = try? storage.load(contextID: contextID) else { report(.loadFailed(pixelName: T.pixelName, error: WidePixelError.flowNotFound(pixelName: T.pixelName)), error: WidePixelError.flowNotFound(pixelName: T.pixelName), params: nil); return }
        var interval = typed[keyPath: keyPath] ?? MeasuredInterval()
        if interval.start != nil { assertionFailure("startMeasurement called but start is already set"); return }
        interval.start = date
        typed[keyPath: keyPath] = interval
        do { try Self.storageQueue.sync { try storage.save(typed) } } catch { report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil) }
    }

    func stopMeasuring<T: WidePixelData>(_ type: T.Type, contextID: UUID, keyPath: WritableKeyPath<T, MeasuredInterval?>, at date: Date) {
        guard var typed: T = try? storage.load(contextID: contextID) else { report(.loadFailed(pixelName: T.pixelName, error: WidePixelError.flowNotFound(pixelName: T.pixelName)), error: WidePixelError.flowNotFound(pixelName: T.pixelName), params: nil); return }
        var interval = typed[keyPath: keyPath] ?? MeasuredInterval()
        if interval.start == nil { interval.start = date }
        interval.end = date
        typed[keyPath: keyPath] = interval
        do { try Self.storageQueue.sync { try storage.save(typed) } } catch { report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil) }
    }

    // MARK: - Instance-based measuring

    public func startMeasuring<T: WidePixelData>(_ data: inout T, keyPath: WritableKeyPath<T, MeasuredInterval?>) {
        var interval = data[keyPath: keyPath] ?? MeasuredInterval()
        if interval.start != nil { assertionFailure("startMeasuring called but start is already set"); return }
        interval.start = Date()
        data[keyPath: keyPath] = interval
        do { try Self.storageQueue.sync { try storage.save(data) } } catch { report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil) }
    }

    public func stopMeasuring<T: WidePixelData>(_ data: inout T, keyPath: WritableKeyPath<T, MeasuredInterval?>) {
        var interval = data[keyPath: keyPath] ?? MeasuredInterval()
        let now = Date()
        if interval.start == nil { interval.start = now }
        interval.end = now
        data[keyPath: keyPath] = interval
        do { try Self.storageQueue.sync { try storage.save(data) } } catch { report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil) }
    }

    // MARK: - Internal Helper Methods

    func clearFlow(for contextID: UUID) {
        Self.storageQueue.sync { storage.clearContext(contextID) }
    }

    private static func generatePixelName(for name: String) -> String {
        return "m_\(PlatformInfo.pixelName)_wide_\(name)"
    }

    // MARK: - Helper Methods for Single Flow Convenience

    func getFirstFlowData<T: WidePixelData>(_ type: T.Type) -> T? {
        guard let contextID = getFirstFlowContextID(type) else { return nil }
        return getFlowData(type, contextID: contextID)
    }

    func getFirstFlowContextID<T: WidePixelData>(_ type: T.Type) -> UUID? {
        return Self.storageQueue.sync { storage.firstContextID(for: T.self) }
    }

    // MARK: - Utility Methods

    public func getActiveFlowNames() -> [String] {
        return Self.storageQueue.sync { storage.getActiveFlowNames() }
    }

    public func clearAllFlows() {
        Self.storageQueue.sync { storage.removeAll() }
    }

    // MARK: - Event Mapping

    private func report(_ event: WidePixelEvents, error: Error?, params: [String: String]?) {
        eventMapping?.fire(event, error: error, parameters: params)
    }
}

// MARK: - Wide Pixel Event Wrapper

struct WidePixelEvent: PixelKitEvent {
    let name: String
    let parameters: [String: String]?

    init(name: String, parameters: [String: String]) {
        self.name = name
        self.parameters = parameters
    }
}

// MARK: - Sampling

public protocol WidePixelSampling {
    func shouldSend(sampleRate: Double) -> Bool
}

public struct DefaultWidePixelSampler: WidePixelSampling {
    public init() {}
    public func shouldSend(sampleRate: Double) -> Bool {
        let rate = max(0.0, min(1.0, sampleRate))
        return Double.random(in: 0..<1) < rate
    }
}

// MARK: - Platform Information

struct PlatformInfo {
    static let displayName: String = {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }()

    static let pixelName: String = {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "mac"
        #else
        return "unknown"
        #endif
    }()

    static let formFactor: String? = {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
        #else
        return nil
        #endif
    }()

    static var appVersion: String {
        return AppVersion.shared.versionAndBuildNumber
    }

    static var appName: String {
        return AppVersion.shared.name
    }
}
