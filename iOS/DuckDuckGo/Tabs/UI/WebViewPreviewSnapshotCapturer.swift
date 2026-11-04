//
//  WebViewPreviewSnapshotCapturer.swift
//  DuckDuckGo
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

import UIKit
import WebKit

/// What `WebViewPreviewSnapshotCapturer` needs from a web view, so tests can stand in for one that never answers.
@MainActor
protocol WebViewSnapshotting: AnyObject {
    var window: UIWindow? { get }
    func takeSnapshot(with snapshotConfiguration: WKSnapshotConfiguration?,
                      completionHandler: @escaping @MainActor @Sendable (UIImage?, (any Error)?) -> Void)
}

extension WKWebView: WebViewSnapshotting {}

@MainActor
struct WebViewPreviewSnapshotCapturer {

    /// Takes a preview of a web view without waiting forever on a frozen page, whose `takeSnapshot` never calls back.
    /// Each snapshot gets `timeout` to answer; late answers are ignored.
    ///
    /// With `waitForScreenUpdates`, the first snapshot waits for the page to draw, and if it times out, one that
    /// doesn't wait is tried. Without it, only the snapshot that doesn't wait is taken.
    func capture(webView: WebViewSnapshotting,
                 rect: CGRect,
                 timeout: TimeInterval,
                 waitForScreenUpdates: Bool,
                 completion: @escaping (UIImage?, WebContentHealthPixel.SnapshotResult) -> Void) {
        guard waitForScreenUpdates else { return snapshotWithoutWaiting(webView,
                                                                        rect: rect,
                                                                        timeout: timeout,
                                                                        completion: completion) }
        // A frozen page never answers, so WebKit keeps this callback for as long as the web view lives.
        // Holding the web view weakly lets it go when its tab closes.
        snapshot(webView, rect: rect, afterScreenUpdates: true, timeout: timeout) { [weak webView] image, timedOut in
            guard timedOut else { return completion(image, .success) }
            guard let webView else { return completion(nil, .retryTimeout) }
            snapshotWithoutWaiting(webView,
                                   rect: rect,
                                   timeout: timeout,
                                   completion: completion)
        }
    }
    
    private func snapshotWithoutWaiting(_ webView: WebViewSnapshotting,
                                        rect: CGRect,
                                        timeout: TimeInterval,
                                        completion: @escaping (UIImage?, WebContentHealthPixel.SnapshotResult) -> Void) {
        snapshot(webView, rect: rect, afterScreenUpdates: false, timeout: timeout) { image, timedOut in
            let result: WebContentHealthPixel.SnapshotResult = timedOut ? .retryTimeout : image == nil ? .retryNoImage : .retryImage
            completion(image, result)
        }
    }

    private static func configuration(rect: CGRect, windowSize: CGSize, afterScreenUpdates: Bool) -> WKSnapshotConfiguration {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        configuration.snapshotWidth = NSNumber(value: WebViewPreviewSnapshotGeometry.snapshotWidth(for: rect, windowSize: windowSize))
        configuration.afterScreenUpdates = afterScreenUpdates
        return configuration
    }

    private func snapshot(_ webView: WebViewSnapshotting,
                          rect: CGRect,
                          afterScreenUpdates: Bool,
                          timeout: TimeInterval,
                          completion: @escaping (_ image: UIImage?, _ timedOut: Bool) -> Void) {
        let configuration = Self.configuration(rect: rect,
                                               windowSize: webView.window?.bounds.size ?? rect.size,
                                               afterScreenUpdates: afterScreenUpdates)
        var didFinish = false
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            guard !didFinish else { return }
            didFinish = true
            completion(nil, true)
        }
        webView.takeSnapshot(with: configuration) { image, _ in
            guard !didFinish else { return }
            didFinish = true
            completion(image, false)
        }
    }
}
