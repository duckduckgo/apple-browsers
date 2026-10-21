//
//  WKWebViewConfigurationExtensionTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import XCTest
import WebKit

class WKWebViewConfigurationExtensionTests: XCTestCase {
    
    func testWhenWebViewCreatedWithNonPersistenceThenDataStoreIsNonPersistent() {
        let configuration = WKWebViewConfiguration.nonPersistent()
        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
    }
    
    @available(iOS 17.0, *)
    @MainActor
    func testWhenWebViewCreatedWithPersistenceThenDataStoreIsPersistentAndDefault() {
        let configuration = WKWebViewConfiguration.persistent(fireMode: false)
        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(webView.configuration.websiteDataStore.identifier, WKWebsiteDataStore.default().identifier)
    }
    
    @available(iOS 17.0, *)
    @MainActor
    func testWhenWebViewCreatedForFireModeThenDataStoreIsPersistentAndNotDefault() {
        let configuration = WKWebViewConfiguration.persistent(fireMode: true)
        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertNotEqual(webView.configuration.websiteDataStore.identifier, WKWebsiteDataStore.default().identifier)
    }
}
