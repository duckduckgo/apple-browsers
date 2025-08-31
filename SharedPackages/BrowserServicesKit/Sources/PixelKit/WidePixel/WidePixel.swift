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
    func completeFlow<T: WidePixelData>(_ data: T, status: WidePixelStatus, onComplete: @escaping PixelKit.CompletionBlock)
    func discardFlow<T: WidePixelData>(_ data: T)
    func getAllFlowData<T: WidePixelData>(_ type: T.Type) -> [T]
}

public final class WidePixel: WidePixelManaging {

    public struct MeasuredInterval: Codable {
        public var start: Date?
        public var end: Date?

        public init(start: Date? = nil, end: Date? = nil) {
            self.start = start
            self.end = end
        }

        public static func startingNow() -> MeasuredInterval {
            return MeasuredInterval(start: Date())
        }

        public mutating func complete(at date: Date = Date()) {
            self.end = date
        }
    }

    private static let logger = Logger(subsystem: "PixelKit", category: "Wide Pixel")
    private static let storageQueue = DispatchQueue(label: "com.duckduckgo.wide-pixel.storage-queue", qos: .utility)

    private let storage: WidePixelStoring
    private let pixelKitProvider: () -> PixelKit?
    private let sampler: WidePixelSampling
    private let eventMapping: EventMapping<WidePixelEvent>?

    public init(storage: WidePixelStoring = WidePixelUserDefaultsStorage(),
                pixelKitProvider: @escaping () -> PixelKit? = { PixelKit.shared },
                sampler: WidePixelSampling? = nil,
                events: EventMapping<WidePixelEvent>? = nil) {
        self.pixelKitProvider = pixelKitProvider
        self.storage = storage
        self.sampler = sampler ?? DefaultWidePixelSampler(storage: self.storage)
        self.eventMapping = events
    }

    // MARK: - Public API

    public func startFlow<T: WidePixelData>(_ data: T) {
        if !shouldSampleFlow(data) {
            Self.logger.info("Wide pixel flow dropped at start due to sample rate for \(T.pixelName, privacy: .public), global ID: \(data.globalData.id, privacy: .public)")
            return
        }

        Self.logger.info("Starting wide pixel flow '\(T.pixelName, privacy: .public)' with global ID: \(data.globalData.id, privacy: .public)")
        do {
            try Self.storageQueue.sync { try storage.save(data) }
        } catch {
            report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
        }
    }

    public func updateFlow<T: WidePixelData>(_ data: T) {
        let globalID = data.globalData.id

        do {
            try Self.storageQueue.sync { try storage.update(data) }
        } catch {
            if case WidePixelError.flowNotFound = error {
                // Expected if the flow wasn't sampled when it was started
                Self.logger.info("Wide pixel update ignored for non-existent flow: \(T.pixelName, privacy: .public), global ID: \(globalID, privacy: .public)")
            } else {
                report(.updateFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
            }
            return
        }

        Self.logger.info("Wide pixel with global ID \(globalID, privacy: .public) updated: \(data.pixelParameters())")
    }

    public func getFlowData<T: WidePixelData>(_ type: T.Type, globalID: String) -> T? {
        return Self.storageQueue.sync { try? storage.load(globalID: globalID) }
    }

    public func getAllFlowData<T: WidePixelData>(_ type: T.Type) -> [T] {
        return Self.storageQueue.sync { storage.allWidePixels(for: T.self) }
    }

    // MARK: - Flow Completion

    public func completeFlow<T: WidePixelData>(_ data: T, status: WidePixelStatus, onComplete: @escaping PixelKit.CompletionBlock = { _, _ in }) {
        guard getFlowData(T.self, globalID: data.globalData.id) != nil else {
            Self.logger.info("Attempted to complete non-existent wide pixel '\(T.pixelName, privacy: .public)' with global ID: \(data.globalData.id, privacy: .public)")
            onComplete(false, nil)
            return
        }

        Self.logger.info("Completing wide pixel '\(T.pixelName, privacy: .public)' with status \(status.description, privacy: .public) and global ID: \(data.globalData.id, privacy: .public)")

        do {
            try storage.update(data)
            let current: T = try storage.load(globalID: data.globalData.id)
            let parameters = try generateFinalParameters(from: current, status: status)
            storage.delete(current)

            try firePixel(named: T.pixelName, parameters: parameters, onComplete: onComplete)

            Self.logger.info("Completed wide pixel flow: \(T.pixelName, privacy: .public) with global ID: \(data.globalData.id, privacy: .public)")
        } catch {
            if case WidePixelError.flowNotFound = error {
                // Expected if the flow wasn't sampled when it was started
                Self.logger.info("Wide pixel completion ignored for non-existent flow: \(T.pixelName, privacy: .public), global ID: \(data.globalData.id, privacy: .public)")
                onComplete(true, nil)
            } else {
                Self.logger.error("Failed to complete wide pixel flow \(T.pixelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                report(.completeFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
                storage.delete(data)
                onComplete(false, error)
            }
        }
    }

    public func discardFlow<T: WidePixelData>(_ data: T) {
        do {
            let current: T = try Self.storageQueue.sync {
                try storage.load(globalID: data.globalData.id)
            }

            Self.storageQueue.sync {
                storage.delete(current)
            }

            Self.logger.info("Discarded wide pixel flow '\(T.pixelName, privacy: .public)' with global ID: \(data.globalData.id, privacy: .public)")
        } catch {
            if case WidePixelError.flowNotFound = error {
                // No-op
            } else {
                Self.logger.error("Failed to discard wide pixel flow \(T.pixelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                report(.discardFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
            }
        }
    }

    private func shouldSampleFlow(_ data: any WidePixelData) -> Bool {
        return sampler.shouldSendPixel(
            sampleRate: Float(data.globalData.sampleRate),
            contextID: data.contextData.id
        )
    }

    private func generateFinalParameters<T: WidePixelData>(from typed: T, status: WidePixelStatus) throws -> [String: String] {
        var parameters: [String: String] = [:]

        parameters.merge(typed.globalData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(typed.appData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(typed.contextData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(typed.pixelParameters(), uniquingKeysWith: { _, new in new })

        parameters[WidePixelParameter.Feature.status] = status.description

        if case let .unknown(reason) = status {
            parameters[WidePixelParameter.Feature.statusReason] = reason
        }

        return parameters
    }

    private func firePixel(named pixelName: String, parameters: [String: String], onComplete: @escaping PixelKit.CompletionBlock) throws {
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
        let widePixelEvent = WidePixelPixelKitEvent(name: finalPixelName, parameters: parameters)

        pixelKit.fire(
            widePixelEvent,
            frequency: .standard,
            withHeaders: nil,
            withAdditionalParameters: nil,
            withError: nil,
            allowedQueryReservedCharacters: nil,
            includeAppVersionParameter: true,
            includePixelSourceParameter: false,
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

    public func completeFlow<T: WidePixelData>(_ type: T.Type, globalID: String, status: WidePixelStatus, onComplete: @escaping PixelKit.CompletionBlock) {
        guard let currentData = getFlowData(T.self, globalID: globalID) else {
            Self.logger.info("Wide pixel completion ignored for non-existent flow: \(T.pixelName, privacy: .public), global ID: \(globalID, privacy: .public)")
            onComplete(true, nil)
            return
        }

        completeFlow(currentData, status: status, onComplete: onComplete)
    }

    private static func generatePixelName(for name: String) -> String {
        #if os(macOS)
        return "m_mac_wide_\(name)"
        #elseif os(iOS)
        return "m_ios_wide_\(name)"
        #else
        fatalError("Unsupported platform, please define a new pixel name if you're adding a new platform")
        #endif
    }

    private func report(_ event: WidePixelEvent, error: Error?, params: [String: String]?) {
        eventMapping?.fire(event, error: error, parameters: params)
    }
}

struct WidePixelPixelKitEvent: PixelKitEvent {
    let name: String
    let parameters: [String: String]?

    init(name: String, parameters: [String: String]) {
        self.name = name
        self.parameters = parameters
    }
}
