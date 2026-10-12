//
//  PageResourceLoadObserverTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Testing
import WebKit

@testable import DDGNavigation

@MainActor
struct PageResourceLoadObserverTests {

    private let webView = WKWebView()
    private let existingDelegate = NSObject()

    @available(iOS 16, macOS 13, *)
    @Test("Attaching when another resource load delegate is set fires resourceLoadDelegateAlreadySet", .timeLimit(.minutes(1)))
    func attachWithExistingDelegateFiresEvent() {
        var events = [PageSignalsEvent]()
        let observer = PageResourceLoadObserver(eventMapping: EventMapping { event, _, _, _ in events.append(event) }) { _, _ in }
        setResourceLoadDelegate(existingDelegate)

        observer.attach(to: webView)

        #expect(events == [.resourceLoadDelegateAlreadySet])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attaching when no resource load delegate is set fires no event", .timeLimit(.minutes(1)))
    func attachWithoutExistingDelegateFiresNoEvent() {
        var events = [PageSignalsEvent]()
        let observer = PageResourceLoadObserver(eventMapping: EventMapping { event, _, _, _ in events.append(event) }) { _, _ in }

        observer.attach(to: webView)

        #expect(events.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Monitor passes its event mapping to the resource load observer", .timeLimit(.minutes(1)))
    func monitorForwardsEventMapping() {
        var events = [PageSignalsEvent]()
        let monitor = PageSignalsMonitor(tld: TLD(), isEnabled: { true }, eventMapping: EventMapping { event, _, _, _ in events.append(event) })
        setResourceLoadDelegate(existingDelegate)

        monitor.attach(to: webView)

        #expect(events == [.resourceLoadDelegateAlreadySet])
    }

    private func setResourceLoadDelegate(_ delegate: AnyObject) {
        webView.perform(NSSelectorFromString("_setResourceLoadDelegate:"), with: delegate)
    }
}
