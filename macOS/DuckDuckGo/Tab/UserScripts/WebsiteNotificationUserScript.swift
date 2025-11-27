//
//  WebsiteNotificationUserScript.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import UserScript
import WebKit
import OSLog

/// UserScript that polyfills the Web Notification API and bridges to native code.
/// Grants permissions by default for testing purposes.
public final class WebsiteNotificationUserScript: NSObject, UserScript {

    public var source: String {
        """
        (function() {
            'use strict';

            const originalNotification = window.Notification;

            class NotificationPolyfill {
                static get permission() {
                    return 'granted';
                }

                static requestPermission(callback) {
                    const result = 'granted';
                    if (callback) {
                        callback(result);
                    }
                    return Promise.resolve(result);
                }

                constructor(title, options = {}) {
                    this.title = title;
                    this.body = options.body || '';
                    this.icon = options.icon || '';
                    this.tag = options.tag || '';
                    this.data = options.data;

                    webkit.messageHandlers.websiteNotification.postMessage({
                        type: 'show',
                        title: this.title,
                        body: this.body,
                        icon: this.icon,
                        tag: this.tag
                    });
                }

                close() {
                    // Will be implemented in a later phase
                }
            }

            // Preserve static properties from original if needed
            NotificationPolyfill.maxActions = originalNotification?.maxActions || 2;

            // Replace window.Notification
            Object.defineProperty(window, 'Notification', {
                value: NotificationPolyfill,
                writable: false,
                configurable: false
            });
        })();
        """
    }

    public var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }

    public var forMainFrameOnly: Bool { false }

    public var messageNames: [String] { ["websiteNotification"] }

    public var requiresRunInPageContentWorld: Bool { true }
}

// MARK: - WKScriptMessageHandler

extension WebsiteNotificationUserScript: WKScriptMessageHandler {

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            Logger.general.error("WebsiteNotificationUserScript: Invalid message format")
            return
        }

        switch type {
        case "show":
            handleShowNotification(body)
        default:
            Logger.general.debug("WebsiteNotificationUserScript: Unknown message type: \(type)")
        }
    }

    private func handleShowNotification(_ body: [String: Any]) {
        let title = body["title"] as? String ?? ""
        let notificationBody = body["body"] as? String ?? ""
        let icon = body["icon"] as? String ?? ""
        let tag = body["tag"] as? String ?? ""

        Logger.general.debug("""
            WebsiteNotificationUserScript: Notification requested
            - Title: \(title)
            - Body: \(notificationBody)
            - Icon: \(icon)
            - Tag: \(tag)
            """)
    }
}

