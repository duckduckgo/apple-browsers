//
//  HTTPSUpgrade.swift
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

import Common
import Foundation
import BloomFilterWrapper
import os.log

public enum HTTPSUpgradeError: Error {
    case badUrl
    case nonHttp
    case domainExcluded
    case featureDisabled
    case nonUpgradable(HTTPSBloomFilterSpecification?)
    case bloomFilterTaskNotSet
    case noBloomFilter
}

public actor HTTPSUpgrade {

    private var dataReloadTask: Task<BloomFilter?, Never>?
    private nonisolated let store: HTTPSUpgradeStore
    private nonisolated let privacyManager: PrivacyConfigurationManaging

    private var bloomFilter: BloomFilter?
    private let logger: Logger

    public init(store: HTTPSUpgradeStore, privacyManager: PrivacyConfigurationManaging, logger: Logger) {
        self.store = store
        self.privacyManager = privacyManager
        self.logger = logger
    }

    @MainActor
    public func upgrade(url: URL) async -> Result<URL, HTTPSUpgradeError> {
        guard url.isHttp else { return .failure(.nonHttp) }
        guard let host = url.host else { return .failure(.badUrl) }
        guard shouldExcludeDomain(host) == false else { return .failure(.domainExcluded) }
        guard isFeatureEnabled(forHost: host, privacyConfig: privacyConfig) else { return .failure(.featureDisabled) }

        switch await self.getBloomFilter() {
        case .success(let bloomFilter):
            guard bloomFilter.containsHost(host) else { return .failure(.nonUpgradable(bloomFilter.specification)) }
            guard let upgradedUrl = url.toHttps() else { return .failure(.badUrl) }

            return .success(upgradedUrl)

        case .failure(let error):
            return .failure(error)
        }
    }

    private nonisolated var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }

    private nonisolated func shouldExcludeDomain(_ host: String) -> Bool { store.hasExcludedDomain(host) }

    private nonisolated func isFeatureEnabled(forHost host: String, privacyConfig: PrivacyConfiguration) -> Bool {
        privacyConfig.isFeature(.httpsUpgrade, enabledForDomain: host)
    }

    private func getBloomFilter() async -> Result<BloomFilter, HTTPSUpgradeError> {
        let result: BloomFilter
        if let bloomFilter {
            result = bloomFilter
        } else if let dataReloadTask {
            guard let bloomFilter = await dataReloadTask.value else { return .failure(.noBloomFilter) }
            result = bloomFilter
        } else {
            return .failure(.bloomFilterTaskNotSet)
        }

        return .success(result)
    }

    nonisolated public func loadDataAsync() {
        logger.debug("loadDataAsync")
        Task {
            await self.loadData()
        }
    }

    public func loadData() async {
        if let dataReloadTask {
            logger.log("Reload already in progress")
            _=await dataReloadTask.value
        }
        dataReloadTask = Task.detached { [store] in
            return store.loadBloomFilter().map { BloomFilter(wrapper: $0.wrapper, specification: $0.specification) }
        }
        self.bloomFilter = await dataReloadTask!.value
        self.dataReloadTask = nil
    }

    private func reloadBloomFilter() async -> BloomFilter? {
        logger.debug("Reloading Bloom Filter")
        let bloomFilter = store.loadBloomFilter().map { BloomFilter(wrapper: $0.wrapper, specification: $0.specification) }
        self.bloomFilter = bloomFilter
        return bloomFilter
    }

    public func persistBloomFilter(specification: HTTPSBloomFilterSpecification, data: Data) throws {
        try store.persistBloomFilter(specification: specification, data: data)
    }

    public func persistExcludedDomains(_ domains: [String]) throws {
        try store.persistExcludedDomains(domains)
    }

}
