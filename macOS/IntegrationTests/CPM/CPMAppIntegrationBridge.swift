//
//  CPMAppIntegrationBridge.swift
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

/// Observes delivery to the production content listener without synthesizing a response.
enum CPMAppIntegrationBridge {
    static let content = #"""
    (() => {
        if (window !== window.top) return;
        const runtime = globalThis.chrome.runtime;
        const marks = {};
        const flush = () => {
            for (const [key, value] of Object.entries(marks)) {
                document.documentElement?.setAttribute('data-cpm-app-' + key, value);
            }
        };
        document.addEventListener('readystatechange', flush);
        const mark = (key, value = String(Math.round(performance.now()))) => {
            marks[key] = value;
            flush();
        };
        mark('loaded');
        document.addEventListener('cpm-app-reinit', () => {
            runtime.sendMessage({ messageType: 'autoconsent', autoconsentPayload: { type: 'init', url: window.location.href } });
        });
        const event = runtime.onMessage;
        const add = event.addListener.bind(event);
        const wrapped = listener => add((message, ...rest) => {
            if (message?.type === 'initResp') mark('initresp');
            return listener(message, ...rest);
        });
        try { event.addListener = wrapped; } catch (_) {}
        if (event.addListener !== wrapped) Object.defineProperty(event, 'addListener', { value: wrapped, configurable: true });
    })();
    """#
}
