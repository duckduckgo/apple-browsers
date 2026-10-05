//
//  PIRLivePreviewDemo.swift
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

#if DEBUG
import WebKit
import DataBrokerProtectionCore

/// Exercises agent capture and XPC without a profile, broker requests, or opt-outs.
@MainActor
final class PIRLivePreviewDemo {
    static let shared = PIRLivePreviewDemo()

    func start() {
        stop()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        self.webView = webView
        PIRLivePreview.shared.register(webView: webView, operationID: operationID,
                                       brokerName: "Local preview demo", activity: "Rendered in the PIR agent")
        webView.loadHTMLString(Self.html, baseURL: nil)
        expiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 90_000_000_000)
            } catch { return }
            self?.stop()
        }
    }

    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        PIRLivePreview.shared.unregister(operationID: operationID)
        webView?.stopLoading()
        webView = nil
    }

    private var webView: WKWebView?
    private var expiryTask: Task<Void, Never>?
    private let operationID = UUID()

    private static let html = """
    <!doctype html>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body { margin: 0; padding: 70px; font: 28px -apple-system; background: #f4f6fa; color: #20242c; }
      h1 { font-size: 44px; margin-bottom: 16px; }
      p { color: #606875; }
      .card { background: white; border-radius: 24px; padding: 36px; margin-top: 40px; }
      .track { height: 24px; background: #e7eaf0; border-radius: 12px; overflow: hidden; }
      #bar { height: 100%; background: #397bf6; transition: width .3s; }
      #counter { font-size: 72px; font-weight: 600; margin: 20px 0; }
    </style>
    <h1>Live preview test</h1>
    <p>This local page runs in the PIR background agent.</p>
    <div class="card">
      <div class="track"><div id="bar"></div></div>
      <div id="counter">0</div>
      <p>No broker requests or opt-outs.</p>
    </div>
    <script>
      let count = 0;
      setInterval(() => {
        document.getElementById('counter').textContent = ++count;
        document.getElementById('bar').style.width = (count % 20) * 5 + '%';
      }, 500);
    </script>
    """
}
#endif
