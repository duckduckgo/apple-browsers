//
//  WebView+ViewportSnapshot.swift
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

#if os(macOS) || DEBUG
import WebKit

@MainActor
private final class ViewportSnapshotRequest {
    private var continuation: CheckedContinuation<CGImage?, Never>?

    init(continuation: CheckedContinuation<CGImage?, Never>) {
        self.continuation = continuation
    }

    func finish(with image: CGImage?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: image)
    }
}

extension WKWebView {
    @MainActor
    func pirViewportSnapshot(in rect: CGRect) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let request = ViewportSnapshotRequest(continuation: continuation)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = rect
            takeSnapshot(with: configuration) { image, _ in
                Task { @MainActor in
#if os(macOS)
                    request.finish(with: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
#else
                    request.finish(with: image?.cgImage)
#endif
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                request.finish(with: nil)
            }
        }
    }
}
#endif
