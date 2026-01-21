//
//  WideEvent.swift
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

public protocol WideEventManaging {
    func startFlow<T: WideEventData>(_ data: T)
    func updateFlow<T: WideEventData>(_ data: T)
    func updateFlow<T: WideEventData>(globalID: String, update: (inout T) -> Void)
    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus, onComplete: @escaping PixelKit.CompletionBlock)
    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus) async throws -> Bool
    func discardFlow<T: WideEventData>(_ data: T)
    func getFlowData<T: WideEventData>(_ type: T.Type, globalID: String) -> T?
    func getAllFlowData<T: WideEventData>(_ type: T.Type) -> [T]
}

public final class WideEvent: WideEventManaging {

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

    private static let logger = Logger(subsystem: "PixelKit", category: "Wide Event")
    private static let storageQueue = DispatchQueue(label: "com.duckduckgo.wide-pixel.storage-queue", qos: .utility)

    private let storage: WideEventStoring
    private let sender: WideEventSending
    private let sampler: WideEventSampling
    private let failureEventMapping: EventMapping<WideEventFailureEvent>?
    private let featureFlagProvider: WideEventFeatureFlagProviding

    public init(storage: WideEventStoring = WideEventUserDefaultsStorage(),
                sender: WideEventSending = DefaultWideEventSender(),
                sampler: WideEventSampling? = nil,
                failureEventMapping: EventMapping<WideEventFailureEvent>? = WideEventFailureEvent.eventMapping,
                featureFlagProvider: WideEventFeatureFlagProviding) {
        self.storage = storage
        self.sender = sender
        self.sampler = sampler ?? DefaultWideEventSampler()
        self.failureEventMapping = failureEventMapping
        self.featureFlagProvider = featureFlagProvider
    }

    // MARK: - Public API

    public func startFlow<T: WideEventData>(_ data: T) {
        if !shouldSampleFlow(data) {
            Self.logger.info("Wide event flow dropped at start due to sample rate for \(T.pixelName, privacy: .public), global ID: \(data.globalData.id, privacy: .public)")
            return
        }

        Self.logger.info("Starting wide event flow '\(T.pixelName, privacy: .public)' with global ID: \(data.globalData.id, privacy: .public)")
        do {
            try Self.storageQueue.sync { try storage.save(data) }
        } catch {
            report(.saveFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
        }
    }

    public func updateFlow<T: WideEventData>(_ data: T) {
        let globalID = data.globalData.id

        do {
            try Self.storageQueue.sync { try storage.update(data) }
            Self.logger.info("Wide event \(globalID, privacy: .public) updated: \(data.pixelParameters())")
        } catch {
            if case WideEventError.flowNotFound = error {
                Self.logger.info("Wide event update ignored for non-existent flow: \(T.pixelName, privacy: .public), global ID: \(globalID, privacy: .public)")
            } else {
                report(.updateFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
            }
        }
    }

    public func updateFlow<T: WideEventData>(globalID: String, update: (inout T) -> Void) {
        do {
            let updatedData = try Self.storageQueue.sync { () -> T in
                var data: T = try storage.load(globalID: globalID)
                update(&data)
                try storage.update(data)
                return data
            }

            Self.logger.info("Wide event \(globalID, privacy: .public) updated: \(updatedData.pixelParameters())")
        } catch {
            if case WideEventError.flowNotFound = error {
                Self.logger.info("Wide event update ignored for non-existent flow: \(T.pixelName, privacy: .public), global ID: \(globalID, privacy: .public)")
            } else {
                report(.updateFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
            }
        }
    }

    public func getFlowData<T: WideEventData>(_ type: T.Type, globalID: String) -> T? {
        return Self.storageQueue.sync { try? storage.load(globalID: globalID) }
    }

    public func getAllFlowData<T: WideEventData>(_ type: T.Type) -> [T] {
        return Self.storageQueue.sync { storage.allWideEvents(for: T.self) }
    }

    // MARK: - Flow Completion

    public func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus, onComplete: @escaping PixelKit.CompletionBlock = { _, _ in }) {
        guard getFlowData(T.self, globalID: data.globalData.id) != nil else {
            Self.logger.info("Attempted to complete non-existent wide event '\(T.pixelName, privacy: .public)' with global ID: \(data.globalData.id, privacy: .public)")
            onComplete(false, nil)
            return
        }

        Self.logger.info("Completing wide event '\(T.pixelName, privacy: .public)' with status \(status.description, privacy: .public) and global ID: \(data.globalData.id, privacy: .public)")

        do {
            try storage.update(data)
            let current: T = try storage.load(globalID: data.globalData.id)
            storage.delete(current)

            sender.send(current, status: status, featureFlagProvider: featureFlagProvider, onComplete: onComplete)

            Self.logger.info("Completed wide event flow: \(T.pixelName, privacy: .public) with global ID: \(data.globalData.id, privacy: .public)")
        } catch {
            if case WideEventError.flowNotFound = error {
                // Expected if the flow wasn't sampled when it was started
                Self.logger.info("Wide event completion ignored for non-existent flow: \(T.pixelName, privacy: .public), global ID: \(data.globalData.id, privacy: .public)")
                onComplete(true, nil)
            } else {
                Self.logger.error("Failed to complete wide event flow \(T.pixelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                report(.completionFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
                storage.delete(data)
                onComplete(false, PixelKitError.externalError(error))
            }
        }
    }

    @discardableResult
    public func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            completeFlow(data, status: status) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: result)
            }
        }
    }

    public func discardFlow<T: WideEventData>(_ data: T) {
        do {
            let current: T = try Self.storageQueue.sync {
                try storage.load(globalID: data.globalData.id)
            }

            Self.storageQueue.sync {
                storage.delete(current)
            }

            Self.logger.info("Discarded wide event flow '\(T.pixelName, privacy: .public)' with global ID: \(data.globalData.id, privacy: .public)")
        } catch {
            if case WideEventError.flowNotFound = error {
                // No-op
            } else {
                Self.logger.error("Failed to discard wide event flow \(T.pixelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                report(.discardFailed(pixelName: T.pixelName, error: error), error: error, params: nil)
            }
        }
    }

    private func shouldSampleFlow(_ data: any WideEventData) -> Bool {
        return sampler.shouldSendPixel(sampleRate: Float(data.globalData.sampleRate))
    }

    public func completeFlow<T: WideEventData>(_ type: T.Type, globalID: String, status: WideEventStatus, onComplete: @escaping PixelKit.CompletionBlock) {
        guard let currentData = getFlowData(T.self, globalID: globalID) else {
            Self.logger.info("Wide event completion ignored for non-existent flow: \(T.pixelName, privacy: .public), global ID: \(globalID, privacy: .public)")
            onComplete(true, nil)
            return
        }

        completeFlow(currentData, status: status, onComplete: onComplete)
    }

    private func report(_ event: WideEventFailureEvent, error: Error?, params: [String: String]?) {
        failureEventMapping?.fire(event, error: error, parameters: params)
    }
}

public struct WideEventPixelKitEvent: PixelKitEvent {
    public let name: String
    public let parameters: [String: String]?
    public let standardParameters: [PixelKitStandardParameter]?

    public init(name: String, parameters: [String: String], standardParameters: [PixelKitStandardParameter]?) {
        self.name = name
        self.parameters = parameters
        self.standardParameters = standardParameters
    }
}
