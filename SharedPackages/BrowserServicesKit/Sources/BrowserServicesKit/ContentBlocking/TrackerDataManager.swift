//
//  TrackerDataManager.swift
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import TrackerRadarKit
import Common

public protocol TrackerDataProvider {

    var downloadedTrackerDataEtag: String? { get }
    var downloadedTrackerData: Data? { get }

}

public class TrackerDataManager {

    public enum ReloadResult: Equatable {
        case embedded
        case embeddedFallback
        case downloaded
    }

    public typealias DataSet = (tds: TrackerData, etag: String)

    private let lock = NSLock()

    private var _fetchedData: DataSet?
    private(set) public var fetchedData: DataSet? {
        get {
            lock.lock()
            let data = _fetchedData
            lock.unlock()
            return data
        }
        set {
            lock.lock()
            _fetchedData = newValue
            lock.unlock()
        }
    }

    private var _embeddedData: DataSet!
    private(set) public var embeddedData: DataSet {
        get {
            lock.lock()
            let data: DataSet
            // List is loaded lazily when needed
            if let embedded = _embeddedData {
                data = embedded
            } else {
                let embedded = embeddedDataProvider.embeddedData
                let trackerData = try? JSONDecoder().decode(TrackerData.self, from: embedded)
                _embeddedData = (trackerData!, embeddedDataProvider.embeddedDataEtag)
                data = _embeddedData
            }
            lock.unlock()
            return data
        }
        set {
            lock.lock()
            _embeddedData = newValue
            lock.unlock()
        }
    }

    public var trackerData: TrackerData {
        if let data = fetchedData {
            return data.tds
        }
        return embeddedData.tds
    }

    private let embeddedDataProvider: EmbeddedDataProvider
    private let errorReporting: EventMapping<ContentBlockerDebugEvents>?

    public init(etag: String?,
                data: Data?,
                embeddedDataProvider: EmbeddedDataProvider,
                errorReporting: EventMapping<ContentBlockerDebugEvents>? = nil) {
        self.embeddedDataProvider = embeddedDataProvider
        self.errorReporting = errorReporting

        reload(etag: etag, data: data)
    }

    @discardableResult
    public func reload(etag: String?, data: Data?) -> ReloadResult {

        let result: ReloadResult

        if let etag = etag,
            let data = data {
            result = .downloaded

            do {
                // This might fail if the downloaded data is corrupt or format has changed unexpectedly
                let data = try JSONDecoder().decode(TrackerData.self, from: data)
                fetchedData = (data, etag)
            } catch {
                errorReporting?.fire(.trackerDataParseFailed, error: error)
                fetchedData = nil
                return .embeddedFallback
            }
        } else {
            fetchedData = nil
            result = .embedded
        }

        return result
    }
}
