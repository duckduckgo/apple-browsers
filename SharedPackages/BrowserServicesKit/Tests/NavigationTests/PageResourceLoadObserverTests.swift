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

#if PRIVATE_PAGE_SIGNALS_ENABLED
import Common
import Foundation
import Testing
import WebKit

@testable import DDGNavigation

@MainActor
struct PageResourceLoadObserverTests {

    private let webView = WKWebView()
    private let observer = PageResourceLoadObserver { _, _ in }

    @available(iOS 16, macOS 13, *)
    @Test("Attaching and detaching set and clear the resource load delegate", .timeLimit(.minutes(1)))
    func attachAndDetachOwnDelegate() {
        observer.attach(to: webView)
        #expect(webView.resourceLoadDelegate === observer)

        observer.detach()
        #expect(webView.resourceLoadDelegate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Another object's resource load delegate is never replaced or cleared", .timeLimit(.minutes(1)))
    func existingDelegateIsPreserved() {
        let existingDelegate = NSObject()
        webView.resourceLoadDelegate = existingDelegate

        observer.attach(to: webView)
        #expect(webView.resourceLoadDelegate === existingDelegate)

        observer.detach()
        #expect(webView.resourceLoadDelegate === existingDelegate)

        withExtendedLifetime(existingDelegate) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attaching when another resource load delegate is set fires resourceLoadDelegateAlreadySet", .timeLimit(.minutes(1)))
    func attachWithExistingDelegateFiresEvent() {
        var events = [PageSignalsEvent]()
        let observer = PageResourceLoadObserver(eventMapping: EventMapping { event, _, _, _ in events.append(event) }) { _, _ in }
        let existingDelegate = NSObject()
        webView.resourceLoadDelegate = existingDelegate

        observer.attach(to: webView)

        #expect(events == [.resourceLoadDelegateAlreadySet])
        withExtendedLifetime(existingDelegate) {}
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
        let existingDelegate = NSObject()
        webView.resourceLoadDelegate = existingDelegate

        monitor.attach(to: webView)

        #expect(events == [.resourceLoadDelegateAlreadySet])
        withExtendedLifetime(existingDelegate) {}
    }
}
#endif
