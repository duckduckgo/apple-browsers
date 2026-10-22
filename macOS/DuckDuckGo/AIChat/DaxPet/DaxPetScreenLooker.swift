//
//  DaxPetScreenLooker.swift
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

import AppKit
import ScreenCaptureKit
import Vision

/// The app the user is in, which Dax can be asked about.
struct DaxPetForegroundApp: Equatable {
    let name: String
    let processIdentifier: pid_t
}

@MainActor
protocol DaxPetScreenLooking {
    /// The app in front, unless it's this browser.
    var foregroundApp: DaxPetForegroundApp? { get }
    /// A screenshot of the app's front window, or `nil` without Screen Recording permission.
    func captureWindow(of app: DaxPetForegroundApp) async -> NSImage?
    /// The text in the app's front window, read on the Mac.
    func readText(of app: DaxPetForegroundApp) async -> String?
}

/// Takes screenshots of the app in front through ScreenCaptureKit, only when asked to.
@MainActor
final class DaxPetScreenLooker: DaxPetScreenLooking {

    /// Screenshots are scaled down to this many pixels on their longest side, enough to read.
    static let maximumDimension: CGFloat = 1280

    /// It goes with Dax's on-device Apple Intelligence, which needs macOS 26.
    static var isSupported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    static func requestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    var foregroundApp: DaxPetForegroundApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return DaxPetForegroundApp(name: app.localizedName ?? app.bundleIdentifier ?? "", processIdentifier: app.processIdentifier)
    }

    func captureWindow(of app: DaxPetForegroundApp) async -> NSImage? {
        guard #available(macOS 26, *), CGPreflightScreenCaptureAccess(),
              let windowID = Self.frontWindowID(of: app.processIdentifier),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let pixelSize = CGSize(width: filter.contentRect.width * CGFloat(filter.pointPixelScale),
                               height: filter.contentRect.height * CGFloat(filter.pointPixelScale))
        let scale = min(1, Self.maximumDimension / max(pixelSize.width, pixelSize.height, 1))
        configuration.width = Int(pixelSize.width * scale)
        configuration.height = Int(pixelSize.height * scale)
        configuration.showsCursor = false

        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Text read off a window is cut to what the on-device model reads.
    static let maximumTextLength = 3000

    func readText(of app: DaxPetForegroundApp) async -> String? {
        guard let image = await captureWindow(of: app)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await Self.recognizeText(in: image)
    }

    /// Vision reads the text on the Mac, off the main thread.
    static func recognizeText(in image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                try? VNImageRequestHandler(cgImage: image).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? nil : String(text.prefix(maximumTextLength)))
            }
        }
    }

    /// Window lists come front to back, so the app's first normal window is the one the user sees.
    private static func frontWindowID(of processIdentifier: pid_t) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let front = windows.first { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == processIdentifier && (window[kCGWindowLayer as String] as? Int) == 0
        }
        return front?[kCGWindowNumber as String] as? CGWindowID
    }
}
