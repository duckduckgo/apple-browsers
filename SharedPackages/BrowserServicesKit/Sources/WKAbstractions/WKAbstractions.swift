//
//  WKAbstractions.swift
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
import WebKit

@MainActor
public protocol DDGWebsiteDataStore {

    var httpCookieStore: DDGHTTPCookieStore { get }

    func removeData(ofTypes types: Set<String>, modifiedSince: Date) async
    func dataRecords(ofTypes types: Set<String>) async -> [DDGWebsiteDataRecord]
    func removeData(ofTypes types: Set<String>, for records: [DDGWebsiteDataRecord]) async

}

@MainActor
public protocol DDGHTTPCookieStore {

    func setCookie(_ cookie: HTTPCookie) async
    func allCookies() async -> [HTTPCookie]
    func deleteCookie(_ cookie: HTTPCookie) async

}

@MainActor
public protocol DDGWebsiteDataRecord {

    var displayName: String { get }

}

public struct WebsiteDataStoreWrapper: DDGWebsiteDataStore {

    let wrapped: WKWebsiteDataStore

    public init(wrapped: WKWebsiteDataStore) {
        self.wrapped = wrapped
    }

    public var httpCookieStore: any DDGHTTPCookieStore {
        return HTTPCookieStoreWrapper(wrapped: wrapped.httpCookieStore)
    }

    public func removeData(ofTypes types: Set<String>, modifiedSince: Date) async {
        await wrapped.removeData(ofTypes: types, modifiedSince: modifiedSince)
    }

    public func dataRecords(ofTypes types: Set<String>) async -> [any DDGWebsiteDataRecord] {
        await wrapped.dataRecords(ofTypes: types).map { record in
            WebsiteDataRecordWrapper(wrapped: record)
        }
    }

    public func removeData(ofTypes types: Set<String>, for records: [any DDGWebsiteDataRecord]) async {
        let unwrappedRecords = records.compactMap { ($0 as? WebsiteDataRecordWrapper)?.wrapped }
        assert(unwrappedRecords.count == records.count)
        await wrapped.removeData(ofTypes: types, for: unwrappedRecords)
    }

}

public struct HTTPCookieStoreWrapper: DDGHTTPCookieStore {

    // Ideally these should not be public, but I need to
    //  bridge between this wrapper and another for subscriptions
    public let wrapped: WKHTTPCookieStore

    public init(wrapped: WKHTTPCookieStore) {
        self.wrapped = wrapped
    }

    public func setCookie(_ cookie: HTTPCookie) async {
        await wrapped.setCookie(cookie)
    }

    public func allCookies() async -> [HTTPCookie] {
        await wrapped.allCookies()
    }

    public func deleteCookie(_ cookie: HTTPCookie) async {
        await wrapped.deleteCookie(cookie)
    }

}

public struct WebsiteDataRecordWrapper: DDGWebsiteDataRecord {

    public var displayName: String {
        wrapped.displayName
    }

    let wrapped: WKWebsiteDataRecord

}
