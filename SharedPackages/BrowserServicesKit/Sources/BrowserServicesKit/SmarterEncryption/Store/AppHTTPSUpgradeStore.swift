//
//  AppHTTPSUpgradeStore.swift
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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

import BloomFilterWrapper
import Common
import Foundation
import CoreData
import Persistence
import os.log

public struct AppHTTPSUpgradeStore: HTTPSUpgradeStore {

    public enum Error: Swift.Error {

        case specMismatch
        case saveError(Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .specMismatch:
                return "The spec and the data do not match."
            case .saveError(let error):
                return "Error occurred while saving data: \(error.localizedDescription)"
            }
        }

    }

    public enum ErrorEvents {
        case dbSaveBloomFilterError
        case dbSaveExcludedHTTPSDomainsError
    }

    private struct EmbeddedBloomData {
        let specification: HTTPSBloomFilterSpecification
        let excludedDomains: [String]
    }

    private let bloomFilterDataURL: URL
    private let embeddedResources: EmbeddedBloomFilterResources
    private let errorEvents: EventMapping<ErrorEvents>?
    private let context: NSManagedObjectContext

    public static var bundle: Bundle { .module }
    private let logger: Logger

    public init(database: CoreDataDatabase,
                bloomFilterDataURL: URL,
                embeddedResources: EmbeddedBloomFilterResources,
                errorEvents: EventMapping<ErrorEvents>?,
                logger: Logger) {
        self.bloomFilterDataURL = bloomFilterDataURL
        self.embeddedResources = embeddedResources
        self.errorEvents = errorEvents
        self.context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "HTTPSUpgrade")
        self.logger = logger
    }

    var storedBloomFilterDataHash: String? {
        return try? Data(contentsOf: bloomFilterDataURL).sha256
    }

    public func loadBloomFilter() -> BloomFilter? {
        let specification: HTTPSBloomFilterSpecification
        if let storedBloomFilterSpecification = self.loadStoredBloomFilterSpecification(),
           storedBloomFilterSpecification.sha256 == storedBloomFilterDataHash {
            specification = storedBloomFilterSpecification
        } else {
            do {
                // writes data to Resource.bloomFilter
                let embeddedData = try loadAndPersistEmbeddedData()
                specification = embeddedData.specification
            } catch {
                assertionFailure("Could not load embedded BloomFilter data: \(error)")
                return nil
            }
        }

        assert(specification == loadStoredBloomFilterSpecification())
        assert(specification.sha256 == storedBloomFilterDataHash)

        logger.log("Loading data from \(bloomFilterDataURL.path) SHA: \(specification.sha256)")
        let wrapper = BloomFilterWrapper(fromPath: bloomFilterDataURL.path,
                                         withBitCount: Int32(specification.bitCount),
                                         andTotalItems: Int32(specification.totalEntries))
        return BloomFilter(wrapper: wrapper, specification: specification)
    }

    func loadStoredBloomFilterSpecification() -> HTTPSBloomFilterSpecification? {
        var specification: HTTPSBloomFilterSpecification?
        context.performAndWait {
            let request: NSFetchRequest<HTTPSStoredBloomFilterSpecification> = HTTPSStoredBloomFilterSpecification.fetchRequest()
            guard let result = (try? request.execute())?.first else { return }
            guard let storedSpecification = HTTPSBloomFilterSpecification.copy(storedSpecification: result) else {
                assertionFailure("could not initialize HTTPSBloomFilterSpecification from Managed")
                return
            }
            guard storedSpecification.bitCount > 0, storedSpecification.totalEntries > 0 else {
                assertionFailure("total entries or bit count == 0")
                return
            }
            specification = storedSpecification
        }
        return specification
    }

    private func loadAndPersistEmbeddedData() throws -> EmbeddedBloomData {
        logger.log("Loading embedded https data")
        let specificationData = try Data(contentsOf: embeddedResources.bloomSpecification)
        let specification = try JSONDecoder().decode(HTTPSBloomFilterSpecification.self, from: specificationData)
        let bloomData = try Data(contentsOf: embeddedResources.bloomFilter)
        let excludedDomainsData = try Data(contentsOf: embeddedResources.excludedDomains)
        let excludedDomains = try JSONDecoder().decode(HTTPSExcludedDomains.self, from: excludedDomainsData)

        try persistBloomFilter(specification: specification, data: bloomData)
        try persistExcludedDomains(excludedDomains.data)

        return EmbeddedBloomData(specification: specification, excludedDomains: excludedDomains.data)
    }

    public func persistBloomFilter(specification: HTTPSBloomFilterSpecification, data: Data) throws {
        guard data.sha256 == specification.sha256 else { throw Error.specMismatch }
        logger.log("Persisting data SHA: \(specification.sha256)")
        try persistBloomFilter(data: data)
        try persistBloomFilterSpecification(specification)
    }

    private func persistBloomFilter(data: Data) throws {
        try data.write(to: bloomFilterDataURL, options: .atomic)
    }

    private func deleteBloomFilter() {
        try? FileManager.default.removeItem(at: bloomFilterDataURL)
    }

    func persistBloomFilterSpecification(_ specification: HTTPSBloomFilterSpecification) throws {
        var saveError: Swift.Error?
        context.performAndWait {
            deleteBloomFilterSpecification()

            let storedEntity = HTTPSStoredBloomFilterSpecification(context: context)
            storedEntity.bitCount = Int64(specification.bitCount)
            storedEntity.totalEntries = Int64(specification.totalEntries)
            storedEntity.errorRate = specification.errorRate
            storedEntity.sha256 = specification.sha256

            do {
                try context.save()
            } catch {
                errorEvents?.fire(.dbSaveBloomFilterError, error: error)
                saveError = error
            }
        }
        if let saveError {
            throw Error.saveError(saveError)
        }
    }

    private func deleteBloomFilterSpecification() {
        context.performAndWait {
            context.deleteAll(matching: HTTPSStoredBloomFilterSpecification.fetchRequest())
        }
    }

    public func hasExcludedDomain(_ domain: String) -> Bool {
        var result = false
        context.performAndWait {
            let request: NSFetchRequest<HTTPSExcludedDomain> = HTTPSExcludedDomain.fetchRequest()
            request.predicate = NSPredicate(format: "domain = %@", domain.lowercased())
            guard let count = try? context.count(for: request) else { return }
            result = count != 0
        }
        return result
    }

    public func persistExcludedDomains(_ domains: [String]) throws {
        logger.debug("Persisting excluded \(domains.count) domains")

        var saveError: Swift.Error?
        context.performAndWait {
            deleteExcludedDomains()

            for domain in domains {
                let storedDomain = HTTPSExcludedDomain(context: context)
                storedDomain.domain = domain.lowercased()
            }
            do {
                try context.save()
            } catch {
                assertionFailure("Could not persist ExcludedDomains")
                errorEvents?.fire(.dbSaveExcludedHTTPSDomainsError, error: error)
                saveError = error
            }
        }
        if let saveError {
            throw Error.saveError(saveError)
        }
    }

    private func deleteExcludedDomains() {
        context.performAndWait {
            context.deleteAll(matching: HTTPSExcludedDomain.fetchRequest())
        }
    }

    func reset() {
        logger.log("Resetting")

        deleteBloomFilterSpecification()
        deleteBloomFilter()
        deleteExcludedDomains()
    }

}
