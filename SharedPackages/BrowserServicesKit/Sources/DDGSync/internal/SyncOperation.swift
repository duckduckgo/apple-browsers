//
//  SyncOperation.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import Gzip
import os.log

final class SyncOperation: Operation, @unchecked Sendable {

    let dataProviders: [DataProviding]
    let storage: SecureStoring
    let crypter: Crypting
    let requestMaker: SyncRequestMaking

    var didStart: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didStart
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didStart = newValue
        }
    }

    var didFinish: ((Error?) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didFinish
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didFinish = newValue
        }
    }

    var didReceiveHTTPRequestError: ((Error) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didReceiveHTTPRequestError
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didReceiveHTTPRequestError = newValue
        }
    }

    init(
        dataProviders: [DataProviding],
        storage: SecureStoring,
        crypter: Crypting,
        requestMaker: SyncRequestMaking
    ) {
        self.dataProviders = dataProviders
        self.storage = storage
        self.crypter = crypter
        self.requestMaker = requestMaker
    }

    override func start() {
        guard !isCancelled else {
            isExecuting = false
            isFinished = true
            return
        }

        isExecuting = true
        isFinished = false

        didStart?()

        Task {
            defer {
                isExecuting = false
                isFinished = true
            }

            do {
                let state = try storage.account()?.state ?? .inactive
                guard state != .inactive else {
                    didFinish?(nil)
                    return
                }

                let providersPendingFirstSync = dataProviders.filter { $0.featureSyncSetupState == .needsRemoteDataFetch }
                if !providersPendingFirstSync.isEmpty {
                    try await sync(fetchOnly: true, dataProviders: providersPendingFirstSync)
                }

                try await sync(fetchOnly: false)
                didFinish?(nil)
            } catch is CancellationError {
                didFinish?(nil)
            } catch {
                didFinish?(error)
            }
        }
    }

    func sync(fetchOnly: Bool) async throws {
        try await sync(fetchOnly: fetchOnly, dataProviders: dataProviders)
    }

    func sync(fetchOnly: Bool, dataProviders: [DataProviding] = []) async throws {
        Logger.sync.debug("Sync Operation Started. Fetch-only: \(String(fetchOnly), privacy: .public)")
        defer {
            Logger.sync.debug("Sync Operation Finished. Fetch-only: \(String(fetchOnly), privacy: .public)")
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for dataProvider in dataProviders {
                group.addTask { [weak self] in
                    guard let self else {
                        return
                    }
                    Logger.sync.debug("Syncing \(dataProvider.feature.name, privacy: .public)")

                    do {
                        try checkCancellation()
                        let syncRequest = try await self.makeSyncRequest(for: dataProvider, fetchOnly: fetchOnly)
                        let clientTimestamp = Date()
                        let httpRequest = try self.makeHTTPRequest(for: dataProvider, with: syncRequest, timestamp: clientTimestamp)

                        try checkCancellation()
                        let httpResult: HTTPResult = try await httpRequest.execute()

                        switch httpResult.response.statusCode {
                        case 200:
                            guard let data = httpResult.data else {
                                throw SyncError.noResponseBody
                            }
                            Logger.sync.debug("Response for \(dataProvider.feature.name, privacy: .public): \(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
                            let syncResult = try self.decodeResponse(with: data, request: syncRequest)
                            try checkCancellation()
                            try await self.handleResponse(for: dataProvider, syncResult: syncResult, fetchOnly: fetchOnly, timestamp: clientTimestamp)
                        case 204, 304:
                            try checkCancellation()
                            try await self.handleResponse(for: dataProvider,
                                                          syncResult: .noData(with: syncRequest),
                                                          fetchOnly: fetchOnly,
                                                          timestamp: clientTimestamp)
                        default:
                            throw SyncError.unexpectedStatusCode(httpResult.response.statusCode)
                        }
                    } catch is CancellationError {
                        Logger.sync.debug("Syncing \(dataProvider.feature.name, privacy: .public) cancelled")
                    } catch {
                        if case SyncError.unexpectedStatusCode = error {
                            didReceiveHTTPRequestError?(error)
                        }
                        Logger.sync.error("Error syncing \(dataProvider.feature.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        dataProvider.handleSyncError(error)
                        throw FeatureError(feature: dataProvider.feature, underlyingError: error)
                    }
                }
            }

            try checkCancellation()

            var errors: [FeatureError] = []

            while let result = await group.nextResult() {
                if case .failure(let error) = result, let featureError = error as? FeatureError {
                    errors.append(featureError)
                }
            }

            if !errors.isEmpty {
                throw SyncOperationError(featureErrors: errors)
            }
        }
    }

    private func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }

    private func makeSyncRequest(for dataProvider: DataProviding, fetchOnly: Bool) async throws -> SyncRequest {
        if fetchOnly {
            return SyncRequest(feature: dataProvider.feature, previousSyncTimestamp: dataProvider.lastSyncTimestamp, sent: [])
        }
        let localChanges: [Syncable] = try await dataProvider.fetchChangedObjects(encryptedUsing: crypter)
        return SyncRequest(feature: dataProvider.feature, previousSyncTimestamp: dataProvider.lastSyncTimestamp, sent: localChanges)
    }

    private func makeHTTPRequest(for dataProvider: DataProviding, with syncRequest: SyncRequest, timestamp: Date) throws -> HTTPRequesting {
        let hasLocalChanges = !syncRequest.sent.isEmpty
        if hasLocalChanges {
            do {
                return try requestMaker.makePatchRequest(with: syncRequest, clientTimestamp: timestamp, isCompressed: true)
            } catch let error as GzipError {
                dataProvider.handleSyncError(SyncError.patchPayloadCompressionFailed(error.errorCode))
                return try requestMaker.makePatchRequest(with: syncRequest, clientTimestamp: timestamp, isCompressed: false)
            }
        }
        return try requestMaker.makeGetRequest(with: syncRequest)
    }

    private func decodeResponse(with data: Data, request: SyncRequest) throws -> SyncResult {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SyncError.unableToDecodeResponse("Failed to decode sync response")
        }

        guard let featurePayload = jsonObject[request.feature.name] as? [String: Any],
              let lastModified = featurePayload["last_modified"] as? String,
              let entries = featurePayload["entries"] as? [[String: Any]]
        else {
            throw SyncError.unexpectedResponseBody
        }
        return SyncResult(request: request, syncTimestamp: lastModified, received: entries.map(Syncable.init(jsonObject:)))
    }

    private func handleResponse(for dataProvider: DataProviding, syncResult: SyncResult, fetchOnly: Bool, timestamp: Date) async throws {
        if fetchOnly {
            try await dataProvider.handleInitialSyncResponse(
                received: syncResult.received,
                clientTimestamp: timestamp,
                serverTimestamp: syncResult.syncTimestamp,
                crypter: crypter
            )
        } else {
            try await dataProvider.handleSyncResponse(
                sent: syncResult.request.sent,
                received: syncResult.received,
                clientTimestamp: timestamp,
                serverTimestamp: syncResult.syncTimestamp,
                crypter: crypter
            )
        }
    }

    // MARK: - Overrides

    override var isAsynchronous: Bool { true }

    override var isExecuting: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isExecuting
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isExecuting))
            _isExecuting = newValue
            didChangeValue(forKey: #keyPath(isExecuting))
        }
    }

    override var isFinished: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isFinished
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isFinished))
            _isFinished = newValue
            didChangeValue(forKey: #keyPath(isFinished))
        }
    }

    private let lock = NSRecursiveLock()
    private var _isExecuting: Bool = false
    private var _isFinished: Bool = false
    private var _didStart: (() -> Void)?
    private var _didFinish: ((Error?) -> Void)?
    private var _didReceiveHTTPRequestError: ((Error) -> Void)?
}
