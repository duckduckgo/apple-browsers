//
//  PrivacyConfigurationManager.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import FoundationExtensions
import ContentBlocking

public protocol EmbeddedDataProvider {

    var embeddedDataEtag: String { get }
    var embeddedData: Data { get }
}

public protocol PrivacyConfigurationManaging: AnyObject {

    var currentConfig: Data { get }
    var updatesPublisher: AnyPublisher<Void, Never> { get }
    var privacyConfig: PrivacyConfiguration { get }
    var internalUserDecider: InternalUserDecider { get }

    @discardableResult func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult

    /// The current config re-encoded for injection into content scripts, without `excludedFeatures`.
    func currentConfigJSON(excludingFeatures excludedFeatures: [String]) -> Data?
}

public extension PrivacyConfigurationManaging {

    func currentConfigJSON(excludingFeatures excludedFeatures: [String]) -> Data? {
        guard let config = try? PrivacyConfigurationData(data: currentConfig) else { return nil }
        return try? config.toJSONData(excludeFeatures: excludedFeatures)
    }
}

public class PrivacyConfigurationManager: PrivacyConfigurationManaging {

    public enum ReloadResult: Equatable {
        case embedded
        case embeddedFallback
        case downloaded
    }

    enum ParsingError: Error {
        case dataMismatch
    }

    public typealias ConfigurationData = (rawData: Data, data: PrivacyConfigurationData, etag: String)

    private let lock = NSLock()
    private let embeddedDataProvider: EmbeddedDataProvider
    private let localProtection: DomainsProtectionStore
    private let errorReporting: EventMapping<ContentBlockerDebugEvents>?
    private let installDate: Date?
    private let locale: Locale

    public let internalUserDecider: InternalUserDecider

    private let updatesSubject = PassthroughSubject<Void, Never>()
    public var updatesPublisher: AnyPublisher<Void, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    private var _fetchedConfigData: ConfigurationData?
    private(set) public var fetchedConfigData: ConfigurationData? {
        get {
            lock.lock()
            let data = _fetchedConfigData
            lock.unlock()
            return data
        }
        set {
            lock.lock()
            _fetchedConfigData = newValue
            lock.unlock()
        }
    }

    private var _embeddedConfigData: ConfigurationData!
    private(set) public var embeddedConfigData: ConfigurationData {
        get {
            lock.lock()

            let data: ConfigurationData
            // List is loaded lazily when needed
            if let embedded = _embeddedConfigData {
                data = embedded
            } else {
                let jsonData = embeddedDataProvider.embeddedData
                // swiftlint:disable:next force_try
                let configData = try! PrivacyConfigurationData(data: jsonData)
                _embeddedConfigData = (jsonData, configData, embeddedDataProvider.embeddedDataEtag)
                data = _embeddedConfigData
            }
            lock.unlock()
            return data
        }
        set {
            lock.lock()
            _embeddedConfigData = newValue
            lock.unlock()
        }
    }

    public init(fetchedETag: String?,
                fetchedData: Data?,
                embeddedDataProvider: EmbeddedDataProvider,
                localProtection: DomainsProtectionStore,
                errorReporting: EventMapping<ContentBlockerDebugEvents>? = nil,
                internalUserDecider: InternalUserDecider,
                locale: Locale = Locale.current,
                installDate: Date? = nil
    ) {
        self.embeddedDataProvider = embeddedDataProvider
        self.localProtection = localProtection
        self.errorReporting = errorReporting
        self.internalUserDecider = internalUserDecider
        self.locale = locale
        self.installDate = installDate

        reload(etag: fetchedETag, data: fetchedData)
    }

    public var privacyConfig: PrivacyConfiguration {
        if let fetchedData = fetchedConfigData {
            return AppPrivacyConfiguration(data: fetchedData.data,
                                           identifier: fetchedData.etag,
                                           localProtection: localProtection,
                                           internalUserDecider: internalUserDecider,
                                           locale: locale,
                                           installDate: installDate)
        }

        return AppPrivacyConfiguration(data: embeddedConfigData.data,
                                       identifier: embeddedConfigData.etag,
                                       localProtection: localProtection,
                                       internalUserDecider: internalUserDecider,
                                       locale: locale,
                                       installDate: installDate)
    }

    public var currentConfig: Data {
        if let fetchedData = fetchedConfigData {
            return fetchedData.rawData
        }
        return embeddedConfigData.rawData
    }

    // Every tab builds two content scope scripts from this JSON, so it's encoded once per config
    // version for each exclusion set. `reload` clears it and bumps the generation, so an encode
    // that races a reload is returned but not stored.
    private let configJSONLock = NSLock()
    private var configJSONCache: [[String]: Data] = [:]
    private var configJSONGeneration = 0

    public func currentConfigJSON(excludingFeatures excludedFeatures: [String]) -> Data? {
        configJSONLock.lock()
        if let cached = configJSONCache[excludedFeatures] {
            configJSONLock.unlock()
            return cached
        }
        let generation = configJSONGeneration
        configJSONLock.unlock()

        let config = fetchedConfigData?.data ?? embeddedConfigData.data
        guard let json = try? config.toJSONData(excludeFeatures: excludedFeatures) else { return nil }

        configJSONLock.lock()
        if generation == configJSONGeneration {
            configJSONCache[excludedFeatures] = json
        }
        configJSONLock.unlock()
        return json
    }

    private func invalidateConfigJSON() {
        configJSONLock.lock()
        configJSONGeneration += 1
        configJSONCache.removeAll()
        configJSONLock.unlock()
    }

    @discardableResult
    public func reload(etag: String?, data: Data?) -> ReloadResult {

        defer {
            invalidateConfigJSON()
            self.updatesSubject.send()
        }

        let result: ReloadResult

        if let etag = etag, let data = data {
            result = .downloaded

            do {
                // This might fail if the downloaded data is corrupt or format has changed unexpectedly
                let configData = try PrivacyConfigurationData(data: data)
                fetchedConfigData = (data, configData, etag)
            } catch {
                errorReporting?.fire(.privacyConfigurationParseFailed, error: error)
                fetchedConfigData = nil
                return .embeddedFallback
            }
        } else {
            fetchedConfigData = nil
            result = .embedded
        }

        return result
    }
}
