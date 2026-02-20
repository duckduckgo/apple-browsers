//
//  WideEventSending.swift
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

public protocol WideEventSending {
    func send<T: WideEventData>(
        _ data: T,
        status: WideEventStatus,
        featureFlagProvider: WideEventFeatureFlagProviding,
        onComplete: @escaping PixelKit.CompletionBlock
    )
}

public final class DefaultWideEventSender: WideEventSending {

    public typealias POSTRequestHandler = (URL, Data, [String: String], @escaping (Bool, Error?) -> Void) -> Void

    private static let logger = Logger(subsystem: "PixelKit", category: "Wide Event Sending")
    private static let postEndpoint = URL(string: "https://improving.duckduckgo.com/e")!

    private let pixelKitProvider: () -> PixelKit?
    private let postRequestHandler: POSTRequestHandler
    private let storage: WideEventStoring

    public init(
        pixelKitProvider: @escaping () -> PixelKit? = { PixelKit.shared },
        postRequestHandler: POSTRequestHandler? = nil,
        storage: WideEventStoring = WideEventUserDefaultsStorage()
    ) {
        self.pixelKitProvider = pixelKitProvider
        self.postRequestHandler = postRequestHandler ?? Self.defaultPOSTRequestHandler
        self.storage = storage
    }

    public func send<T: WideEventData>(
        _ data: T,
        status: WideEventStatus,
        featureFlagProvider: WideEventFeatureFlagProviding,
        onComplete: @escaping PixelKit.CompletionBlock
    ) {
        guard let pixelName = Self.generatePixelName(for: T.metadata.pixelName) else {
            Self.logger.warning("Cannot fire wide event: empty pixel name")
            onComplete(false, WideEventError.emptyPixelName)
            return
        }

        let isFirstDailyOccurrence = checkFirstDailyOccurrence(for: T.metadata.type)
        let parameters = generateFinalParameters(from: data, status: status, isFirstDailyOccurrence: isFirstDailyOccurrence)

        guard !parameters.isEmpty else {
            Self.logger.warning("Cannot fire wide event: empty parameters \(pixelName, privacy: .public)")
            onComplete(false, WideEventError.invalidParameters("Parameters should not be empty"))
            return
        }

        firePixels(pixelName: pixelName, parameters: parameters, onComplete: onComplete)
        storage.recordSentTimestamp(for: T.metadata.type, date: Date())

        if featureFlagProvider.isEnabled(.postEndpoint) {
            sendPOSTRequest(data: data, status: status, isFirstDailyOccurrence: isFirstDailyOccurrence)
        }
    }

    private func checkFirstDailyOccurrence(for eventType: String) -> Bool {
        guard let lastSent = storage.lastSentTimestamp(for: eventType) else {
            return true
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        return !calendar.isDateInToday(lastSent)
    }

    private func generateFinalParameters<T: WideEventData>(from data: T, status: WideEventStatus, isFirstDailyOccurrence: Bool) -> [String: String] {
        var parameters: [String: String] = [:]

        parameters.merge(T.metadata.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(data.globalData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(data.appData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(data.contextData.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(data.pixelParameters(), uniquingKeysWith: { _, new in new })

        if let errorData = data.errorData {
            parameters.merge(errorData.pixelParameters(), uniquingKeysWith: { _, new in new })
        }

        parameters[WideEventParameter.Feature.name] = T.metadata.featureName
        parameters[WideEventParameter.Feature.status] = status.description

        switch status {
        case .success(let reason?), .unknown(let reason):
            parameters[WideEventParameter.Feature.statusReason] = reason
        case .failure, .cancelled, .success(nil):
            break
        }

        if isFirstDailyOccurrence {
            parameters[WideEventParameter.Global.isFirstDailyOccurrence] = "true"
        }

        return parameters
    }

    private static func generatePixelName(for name: String) -> String? {
        guard !name.isEmpty else {
            return nil
        }

        #if os(macOS)
        return "m_mac_wide_\(name)"
        #elseif os(iOS)
        return "m_ios_wide_\(name)"
        #else
        fatalError("Unsupported platform, please define a new pixel name if you're adding a new platform")
        #endif
    }

    private func firePixels(pixelName: String, parameters: [String: String], onComplete: @escaping PixelKit.CompletionBlock) {
        guard let pixelKit = pixelKitProvider() else {
            Self.logger.error("Cannot fire wide event: PixelKit not initialized")
            onComplete(false, WideEventError.invalidFlowState)
            return
        }

        let event = WideEventPixelKitEvent(name: pixelName, parameters: parameters, standardParameters: [])

        pixelKit.fire(
            event,
            frequency: .daily,
            withHeaders: nil,
            withAdditionalParameters: nil,
            allowedQueryReservedCharacters: nil,
            includeAppVersionParameter: true,
            onComplete: { success, error in
                if success {
                    Self.logger.info("Daily wide event pixel sent successfully: \(pixelName, privacy: .public)")
                } else {
                    Self.logger.error("Daily wide event failed to send: \(pixelName, privacy: .public), error: \(String(describing: error), privacy: .public)")
                }
            }
        )

        pixelKit.fire(
            event,
            frequency: .standard,
            withHeaders: nil,
            withAdditionalParameters: nil,
            allowedQueryReservedCharacters: nil,
            includeAppVersionParameter: true,
            onComplete: { success, error in
                if success {
                    Self.logger.info("Wide event sent successfully: \(pixelName, privacy: .public)")
                } else {
                    Self.logger.error("Wide event failed to fire: \(pixelName, privacy: .public), error: \(String(describing: error), privacy: .public)")
                }
                onComplete(success, error)
            }
        )
    }

    private func sendPOSTRequest<T: WideEventData>(data: T, status: WideEventStatus, isFirstDailyOccurrence: Bool) {
        let parameters = generateJSONParameters(from: data, status: status, isFirstDailyOccurrence: isFirstDailyOccurrence)
        let nested = nestedDictionary(from: parameters)

        guard let jsonData = try? JSONSerialization.data(withJSONObject: nested, options: []) else {
            Self.logger.error("Failed to build JSON payload for wide event POST request")
            return
        }

        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        Self.logger.info("Wide event POST request:\nEndpoint: \(Self.postEndpoint.absoluteString, privacy: .public)\nPayload: \(jsonString, privacy: .public)")

        let headers = ["Content-Type": "application/json"]

        postRequestHandler(Self.postEndpoint, jsonData, headers) { success, error in
            if success {
#if DEBUG || REVIEW || ALPHA
                Self.logger.info("Wide event POST request skipped due to non-release build configuration")
#else
                Self.logger.info("Wide event POST request sent successfully")
#endif
            } else {
                Self.logger.error("Wide event POST request failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func generateJSONParameters<T: WideEventData>(from data: T, status: WideEventStatus, isFirstDailyOccurrence: Bool) -> [String: Encodable] {
        var parameters: [String: Encodable] = [:]

        parameters.merge(T.metadata.jsonParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(data.globalData.jsonParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(data.appData.jsonParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(data.contextData.jsonParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(data.jsonParameters(), uniquingKeysWith: { _, new in new })

        if let errorData = data.errorData {
            parameters.merge(errorData.jsonParameters(), uniquingKeysWith: { _, new in new })
        }

        parameters[WideEventParameter.Feature.name] = T.metadata.featureName
        parameters[WideEventParameter.Feature.status] = status.description

        switch status {
        case .success(let reason?), .unknown(let reason):
            parameters[WideEventParameter.Feature.statusReason] = reason
        case .failure, .cancelled, .success(nil):
            break
        }

        if isFirstDailyOccurrence {
            parameters[WideEventParameter.Global.isFirstDailyOccurrence] = true
        }

        return parameters
    }

    private func nestedDictionary(from parameters: [String: Any]) -> [String: Any] {
        var root: [String: Any] = [:]

        for key in parameters.keys.sorted() {
            guard let value = parameters[key] else {
                continue
            }

            let parts = key.split(separator: ".").map(String.init)
            assign(value: value, path: parts, dict: &root)
        }

        return root
    }

    private func assign(value: Any, path: [String], dict: inout [String: Any]) {
        guard let first = path.first else {
            return
        }

        if path.count == 1 {
            dict[first] = value
            return
        }

        var child = dict[first] as? [String: Any] ?? [:]
        assign(value: value, path: Array(path.dropFirst()), dict: &child)
        dict[first] = child
    }

    private static func defaultPOSTRequestHandler(
        url: URL,
        body: Data,
        headers: [String: String],
        onComplete: @escaping (Bool, Error?) -> Void
    ) {
#if DEBUG || REVIEW || ALPHA
        // Avoid sending real POST events when running debug mode, since we can't talk to the staging environment from
        // the client environment directly:
        onComplete(true, nil)
        return
#else
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        URLSession.shared.dataTask(with: request) { _, response, error in
            let success: Bool

            if let http = response as? HTTPURLResponse {
                success = (200...299).contains(http.statusCode)
            } else {
                success = false
            }

            onComplete(success, error)
        }.resume()
#endif
    }
}
