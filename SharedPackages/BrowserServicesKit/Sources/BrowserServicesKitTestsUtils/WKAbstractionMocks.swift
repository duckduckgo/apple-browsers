//
//  WKAbstractionMocks.swift
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
import WKAbstractions

public class MockWebsiteDataStore: DDGWebsiteDataStore {

    public struct TypesAndRecords {
        public let types: Set<String>
        public let records: [DDGWebsiteDataRecord]
    }

    public struct TypesModifiedSince {
        public let types: Set<String>
        public let modifiedSince: Date
    }

    public var removedDataOfTypesForRecords = [TypesAndRecords]()
    public var removedDataOfTypesModifiedSince = [TypesModifiedSince]()

    public var dataRecordsOfTypesReturnValue: [MockWebsiteDataRecord]
    public var httpCookieStore: any DDGHTTPCookieStore

    public init(httpCookieStore: any DDGHTTPCookieStore, dataRecordsOfTypesReturnValue: [MockWebsiteDataRecord] = []) {
        self.httpCookieStore = httpCookieStore
        self.dataRecordsOfTypesReturnValue = dataRecordsOfTypesReturnValue
    }

    public init(dataRecordsOfTypesReturnValue: [DDGWebsiteDataRecord] = []) {
        self.httpCookieStore = MockHTTPCookieStore()
        self.dataRecordsOfTypesReturnValue = []
    }

    public func removeData(ofTypes types: Set<String>, modifiedSince: Date) async {
        removedDataOfTypesModifiedSince.append(TypesModifiedSince(types: types, modifiedSince: modifiedSince))
    }

    public func dataRecords(ofTypes types: Set<String>) async -> [MockWebsiteDataRecord] {
        return dataRecordsOfTypesReturnValue
    }

    public func removeData(ofTypes types: Set<String>, for records: [MockWebsiteDataRecord]) async {
        removedDataOfTypesForRecords.append(TypesAndRecords(types: types, records: records))
    }

}

public class MockHTTPCookieStore: DDGHTTPCookieStore {

    public let allCookiesReturnValue: [HTTPCookie]
    public var cookiesThatWereSet = [HTTPCookie]()
    public var cookiesThatWereDeleted = [HTTPCookie]()

    public init(allCookiesReturnValue: [HTTPCookie] = []) {
        self.allCookiesReturnValue = allCookiesReturnValue
    }

    public func setCookie(_ cookie: HTTPCookie) async {
        cookiesThatWereSet.append(cookie)
    }

    public func allCookies() async -> [HTTPCookie] {
        return allCookiesReturnValue
    }

    public func deleteCookie(_ cookie: HTTPCookie) async {
        cookiesThatWereDeleted.append(cookie)
    }

}

public struct MockWebsiteDataRecord: DDGWebsiteDataRecord {

    public let displayName: String

    public init(displayName: String) {
        self.displayName = displayName
    }

}
