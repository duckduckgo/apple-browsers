//
//  WebPushSPI.swift
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

import Foundation
import OSLog
import WebKit

// MARK: - Private WebKit SPI bridges
//
// These protocols mirror methods declared in WebKit's private headers
// (WKWebsiteDataStorePrivate.h, _WKWebsiteDataStoreDelegate.h).
// We can call into them from Swift via an `as AnyObject as!` cast — Obj-C
// method dispatch is selector-based at runtime, so the cast only succeeds if
// the underlying object responds to the selector. PoC only.

/// Mirrors `-[WKWebsiteDataStore _processPushMessage:completionHandler:]` from
/// `WKWebsiteDataStorePrivate.h` (macOS 13.0+).
@objc protocol _DDGWebPushDataStoreSPI {
    @objc(_processPushMessage:completionHandler:)
    func processPushMessage(_ message: [AnyHashable: Any], completionHandler: @escaping (Bool) -> Void)
}

/// Mirrors `-[WKPreferences _setPushAPIEnabled:]` from `WKPreferencesPrivate.h`.
/// In our build, the Push API is off by default — `PushManager` doesn't appear
/// on `window`, so the JS shim has nothing to monkey-patch. Enabling this
/// makes `PushManager` exist so our prototype-overrides take effect.
@objc protocol _DDGWKPreferencesSPI {
    @objc(_setPushAPIEnabled:)
    func setPushAPIEnabled(_ enabled: Bool)
}

/// Class-method SPI for accessing the SW-side notification manager singleton.
@objc protocol _DDGSWNotificationManagerSPI {
    @objc(_sharedServiceWorkerNotificationManager)
    static func sharedServiceWorkerNotificationManager() -> OpaquePointer
}

// WebKit C API (declared via @_silgen_name so we don't need a bridging header).
// Symbols exported by the WebKit framework binary.

@_silgen_name("WKStringCreateWithUTF8CString")
private func WKStringCreateWithUTF8CString(_ cString: UnsafePointer<CChar>) -> OpaquePointer

@_silgen_name("WKSecurityOriginCreate")
private func WKSecurityOriginCreate(_ protocol_: OpaquePointer, _ host: OpaquePointer, _ port: Int32) -> OpaquePointer

@_silgen_name("WKNotificationManagerProviderDidUpdateNotificationPolicy")
private func WKNotificationManagerProviderDidUpdateNotificationPolicy(_ manager: OpaquePointer, _ origin: OpaquePointer, _ allowed: Bool)

@_silgen_name("WKRelease")
private func WKRelease(_ ref: OpaquePointer)

/// Grants the SW-side notification permission for the given origin so that
/// `self.registration.showNotification(...)` calls inside a `push` handler
/// pass WebKit's `WebNotificationManager::policyForOrigin` check.
enum WebPushNotificationPermission {
    private static let log = Logger(subsystem: "com.duckduckgo.macos.browser", category: "WebPush")

    static func grant(scheme: String, host: String, port: Int) {
        let classSPI: _DDGSWNotificationManagerSPI.Type =
            unsafeBitCast(WKWebsiteDataStore.self, to: _DDGSWNotificationManagerSPI.Type.self)
        let manager = classSPI.sharedServiceWorkerNotificationManager()

        let schemeRef = scheme.withCString(WKStringCreateWithUTF8CString)
        let hostRef = host.withCString(WKStringCreateWithUTF8CString)
        let originRef = WKSecurityOriginCreate(schemeRef, hostRef, Int32(port))

        WKNotificationManagerProviderDidUpdateNotificationPolicy(manager, originRef, true)
        log.info("🟣 [native] granted SW notif permission for \(scheme, privacy: .public)://\(host, privacy: .public):\(port, privacy: .public)")

        WKRelease(originRef)
        WKRelease(hostRef)
        WKRelease(schemeRef)
    }
}

/// Mirrors `<_WKWebsiteDataStoreDelegate>` methods we need from
/// `_WKWebsiteDataStoreDelegate.h`. Called by WebKit when a Service Worker
/// invokes `self.registration.showNotification(...)` and when the network
/// process needs to know which origins have notification permission.
///
/// The `notificationData` parameter is a `_WKNotificationData` instance; we
/// read its fields via KVC (see `WebPushNotificationDelegate`).
@objc protocol _DDGWebsiteDataStoreDelegate {
    @objc(websiteDataStore:showNotification:)
    optional func websiteDataStore(_ dataStore: WKWebsiteDataStore, showNotification notificationData: NSObject)

    @objc(notificationPermissionsForWebsiteDataStore:)
    optional func notificationPermissions(for dataStore: WKWebsiteDataStore) -> [String: NSNumber]
}

// MARK: - WKWebsiteDataStore convenience

extension WKWebsiteDataStore {

    /// Dispatches a synthetic Web Push at the Service Worker registered for
    /// `registrationURL`. Routes through WebKit's regular push pipeline but
    /// bypasses webpushd / APNs entirely. PoC only.
    ///
    /// Dictionary schema mirrors what WebKit's own `_getPendingPushMessage`
    /// produces (see `WebPushMessage::toDictionary()` in
    /// `Source/WebKit/Shared/Cocoa/WebPushMessageCocoa.mm`).
    @available(macOS 13.0, *)
    @discardableResult
    func ddg_processPushMessage(registrationURL: URL, pushData: Data?, partition: String? = nil) async -> Bool {
        let resolvedPartition = partition ?? (value(forKey: "_webPushPartition") as? String) ?? ""
        let dictionary: [AnyHashable: Any] = [
            "WebKitPushRegistrationURL": registrationURL,
            "WebKitPushData": pushData ?? NSNull(),
            "WebKitPushPartition": resolvedPartition,
            "WebKitNotificationPayload": NSNull()
        ]
        let webPushLog = Logger(subsystem: "com.duckduckgo.macos.browser", category: "WebPush")
        webPushLog.info("🟣 [native] _processPushMessage: scope=\(registrationURL.absoluteString, privacy: .public) partition=\"\(resolvedPartition, privacy: .public)\" bytes=\(pushData?.count ?? 0, privacy: .public)")
        let wasProcessed: Bool = await withCheckedContinuation { continuation in
            // `as!` would check formal protocol conformance, which the
            // private SPI doesn't declare. `unsafeBitCast` bypasses that —
            // dispatch is by ObjC selector at runtime, so this is safe as
            // long as the underlying object responds to the selector.
            let spi = unsafeBitCast(self, to: _DDGWebPushDataStoreSPI.self)
            spi.processPushMessage(dictionary) { processed in
                continuation.resume(returning: processed)
            }
        }
        webPushLog.info("🟣 [native] _processPushMessage: returned \(wasProcessed, privacy: .public)")
        return wasProcessed
    }

    /// Sets WebKit's `_delegate` on the data store so the embedder receives
    /// SW-side `registration.showNotification()` callbacks. The property is
    /// `weak`, so the caller must keep the delegate alive.
    func ddg_setPushDelegate(_ delegate: NSObject?) {
        setValue(delegate, forKey: "_delegate")
    }
}
