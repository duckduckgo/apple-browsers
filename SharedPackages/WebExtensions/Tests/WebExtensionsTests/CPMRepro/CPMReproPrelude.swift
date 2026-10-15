//
//  CPMReproPrelude.swift
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

/// Builds JavaScript prepended to the embedded extension's background service worker.
///
/// The prelude only sits at the boundary between CPM and the WebExtension APIs that WebKit
/// implements. Each rule makes selected calls of one API slower, or withholds their reply
/// entirely, which is what CPM would observe if WebKit delivered that reply late or never.
struct CPMReproPrelude: Encodable {

    enum Mode: String, Encodable {
        /// Calls the API after `ms` milliseconds.
        case delay
        /// Calls the API but never settles the promise returned to CPM.
        case withhold
    }

    struct Rule: Encodable {
        /// One of `storage.session.get`, `storage.session.set`, `runtime.sendNativeMessage`, `tabs.sendMessage`.
        let api: String
        let mode: Mode
        var ms: Int = 0
        /// 1-based call numbers the rule applies to; `nil` applies it to every call.
        var calls: [Int]?
    }

    var rules: [Rule] = []
    /// Busy-waits while the worker script evaluates, keeping the background "loading" longer.
    var startupBusyWaitMs = 0
    /// Holds the service worker in the activating state for this long.
    var activateDelayMs = 0
    /// Sends `cpmRepro.log` native notifications with background-side timings.
    var traceMessages = true

    func javaScript() throws -> String {
        let data = try JSONEncoder().encode(self)
        let json = String(bytes: data, encoding: .utf8) ?? "{}"
        return Self.template.replacingOccurrences(of: "__CPM_REPRO_CONFIG__", with: json)
    }

    /// Prepended to the CPM content script. Records, as attributes on the document element (shared
    /// with the page world), when the script ran, when `init` was sent and settled, and when
    /// `initResp` arrived. Times are `performance.now()` milliseconds since navigation start.
    static let contentScript = #"""
    // cpm-repro content prelude: test-only instrumentation, no behavior change.
    (() => {
      const marks = {};
      const flush = () => {
        const el = document.documentElement;
        if (!el) return;
        for (const [k, v] of Object.entries(marks)) el.setAttribute(`data-cpm-repro-${k}`, v);
      };
      document.addEventListener("readystatechange", flush);
      const mark = (k, v) => { if (!(k in marks)) marks[k] = v ?? String(Math.round(performance.now())); flush(); };
      const install = (owner, key, replacement) => {
        try { owner[key] = replacement; } catch (e) {}
        if (owner[key] !== replacement) Object.defineProperty(owner, key, { value: replacement, configurable: true, writable: true });
      };
      if (window !== window.top) return;
      mark("loaded");
      const runtime = globalThis.chrome.runtime;
      const send = runtime.sendMessage.bind(runtime);
      install(runtime, "sendMessage", (msg, ...rest) => {
        if (msg?.autoconsentPayload?.type !== "init") return send(msg, ...rest);
        mark("init-sent");
        const promise = send(msg, ...rest);
        promise.then(() => mark("init-settled"), (e) => mark("init-error", String(e)));
        return promise;
      });
      // Lets the test ask an already loaded document to send CPM's `init` again.
      document.addEventListener("cpm-repro-reinit", () => {
        const stamp = (k) => document.documentElement.setAttribute(`data-cpm-repro-${k}`, String(Math.round(performance.now())));
        stamp("reinit-sent");
        const msg = { messageType: "autoconsent", autoconsentPayload: { type: "init", url: window.location.href } };
        send(msg).then(() => stamp("reinit-settled"), () => stamp("reinit-error"));
      });
      const addListener = runtime.onMessage.addListener.bind(runtime.onMessage);
      install(runtime.onMessage, "addListener", (listener) => addListener((m, s, r) => {
        if (m?.type === "initResp") mark("initresp");
        return listener(m, s, r);
      }));
    })();
    """#

    private static let template = #"""
    // cpm-repro prelude: test-only fault injection at the WebExtension API boundary.
    (() => {
      const config = __CPM_REPRO_CONFIG__;
      const api = globalThis.browser ?? globalThis.chrome;
      const nativeSend = api.runtime.sendNativeMessage.bind(api.runtime);
      const log = (message) => {
        if (!config.traceMessages) return;
        const msg = { context: "cpmRepro", featureName: "cpmRepro", method: "log", params: { message } };
        try { nativeSend("com.duckduckgo.macos.browser", msg).catch(() => {}); } catch (e) {}
      };
      const targets = {
        "storage.session.get": () => [api.storage.session, "get"],
        "storage.session.set": () => [api.storage.session, "set"],
        "runtime.sendNativeMessage": () => [api.runtime, "sendNativeMessage"],
        "tabs.sendMessage": () => [api.tabs, "sendMessage"],
      };
      const counters = {};
      const install = (owner, key, replacement) => {
        try { owner[key] = replacement; } catch (e) {}
        if (owner[key] === replacement) return true;
        try { Object.defineProperty(owner, key, { value: replacement, configurable: true, writable: true }); } catch (e) {}
        return owner[key] === replacement;
      };
      const invoke = (label, n, owner, original, args) => {
        const rule = config.rules.find((r) => r.api === label && (r.calls == null || r.calls.includes(n)));
        if (!rule) return original.apply(owner, args);
        log(`fault ${rule.mode} ${label} #${n}`);
        if (rule.mode === "withhold") {
          original.apply(owner, args);
          return new Promise(() => {});
        }
        return new Promise((resolve) => setTimeout(resolve, rule.ms)).then(() => original.apply(owner, args));
      };
      // Reports API calls whose reply is slow or never arrives, whatever the cause.
      const traced = (label, n, promise) => {
        if (!config.traceMessages || !(promise instanceof Promise)) return promise;
        const started = Date.now();
        let settled = false;
        setTimeout(() => { if (!settled) log(`pending ${label} #${n} > 3000ms`); }, 3000);
        const done = (outcome) => {
          settled = true;
          const ms = Date.now() - started;
          if (ms > 1000 || outcome !== "ok") log(`settled ${label} #${n} ${outcome} after ${ms}ms`);
        };
        promise.then(() => done("ok"), (e) => done(`error ${e}`));
        return promise;
      };
      const wrap = (label) => {
        const [owner, key] = targets[label]();
        const original = owner[key];
        const replacement = function (...args) {
          const n = counters[label] = (counters[label] || 0) + 1;
          return traced(label, n, invoke(label, n, owner, original, args));
        };
        const installed = install(owner, key, replacement);
        if (!installed) log(`failed to wrap ${label}`);
      };
      const labels = config.traceMessages ? Object.keys(targets) : config.rules.map((r) => r.api);
      new Set(labels).forEach(wrap);

      if (config.traceMessages) {
        const addListener = api.runtime.onMessage.addListener.bind(api.runtime.onMessage);
        install(api.runtime.onMessage, "addListener", (listener) => addListener((req, sender, sendResponse) => {
          const payload = req?.autoconsentPayload;
          if (payload?.type === "init") log(`recv init tab=${sender.tab?.id} frame=${sender.frameId} url=${sender.url}`);
          return listener(req, sender, sendResponse);
        }));
      }
      if (config.traceMessages) {
        self.addEventListener("install", () => log("sw install"));
        self.addEventListener("activate", () => log("sw activate"));
      }
      if (config.activateDelayMs > 0) {
        self.addEventListener("activate", (e) => e.waitUntil(new Promise((r) => setTimeout(r, config.activateDelayMs))));
      }
      if (config.startupBusyWaitMs > 0) {
        const until = Date.now() + config.startupBusyWaitMs;
        while (Date.now() < until) {}
      }
      log("prelude evaluated");
    })();
    """#
}
