//
//  AIChatScreenshotCapture.swift
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
import CoreGraphics
import Persistence
import PixelKit

/// Raw values match the NTP `screenshot-mode` schema.
enum AIChatScreenshotMode: String {
    case dragToSelect
    case selectWindowOrDisplay
}

/// Raw values match the pixel `kind` parameter and the NTP `screenshot-kind` schema.
enum AIChatScreenshotKind: String {
    case selection
    case screen
    case window
}

/// Raw values match the pixel `reason` parameter.
enum AIChatScreenshotFailureReason: String {
    case denied
    case unavailable
    case failed
}

enum AIChatScreenshotImageFormat: String {
    case png
    case jpeg
}

/// A capture ready to attach. It only ever lives in memory.
struct AIChatProcessedScreenshot {
    let image: CGImage
    let data: Data
    let format: AIChatScreenshotImageFormat
    let kind: AIChatScreenshotKind
}

enum AIChatScreenshotCaptureResult {
    case image(AIChatProcessedScreenshot)
    case cancelled
    /// Screen Recording is off. The caller shows `presentPermissionAlert(on:)`, which explains before macOS asks.
    case permissionDenied
    case failed(AIChatScreenshotFailureReason)

    /// The `screenshot_failed` reason; `nil` for an image or a cancel, which fire no failure.
    var failureReason: AIChatScreenshotFailureReason? {
        switch self {
        case .image, .cancelled: nil
        case .permissionDenied: .denied
        case .failed(let reason): reason
        }
    }
}

/// Screenshots are mostly text, so they keep 1024 px where picked images get 512.
enum AIChatScreenshotImageProcessor {

    static let maxDimension = 1024
    static let pngByteLimit = 2 * 1024 * 1024
    static let jpegQuality = 0.85

    static func process(_ image: CGImage, kind: AIChatScreenshotKind) -> AIChatProcessedScreenshot? {
        encode(image).map { AIChatProcessedScreenshot(image: $0.image, data: $0.data, format: $0.format, kind: kind) }
    }

    /// Also used for pasted images.
    static func encode(_ image: CGImage) -> (image: CGImage, data: Data, format: AIChatScreenshotImageFormat)? {
        guard let scaled = downscaled(image) else { return nil }

        let bitmap = NSBitmapImageRep(cgImage: scaled)
        if let png = bitmap.representation(using: .png, properties: [:]), png.count <= pngByteLimit {
            return (scaled, png, .png)
        }
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]) else { return nil }
        return (scaled, jpeg, .jpeg)
    }

    /// Never upscales.
    static func scaledSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let longSide = max(width, height)
        guard longSide > maxDimension else { return (width, height) }

        let scale = Double(maxDimension) / Double(longSide)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    private static func downscaled(_ image: CGImage) -> CGImage? {
        let size = scaledSize(width: image.width, height: image.height)
        guard size.width != image.width || size.height != image.height else { return image }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: size.width,
                                      height: size.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }
}

/// Both screenshot modes need Screen Recording. macOS is only asked from our alert, so the alert's
/// explanation always comes first.
struct AIChatScreenRecordingPermission {

    private static let askedKey = "aichat.screenshot.screen-recording-asked"

    var isGranted: () -> Bool = { CGPreflightScreenCaptureAccess() }
    var requestAccess: () -> Void = { _ = CGRequestScreenCaptureAccess() }
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard

    /// macOS shows its prompt only the first time it's asked and never says whether it has, so we remember asking.
    var hasAskedMacOS: Bool {
        (try? keyValueStore.object(forKey: Self.askedKey)) as? Bool == true
    }

    /// macOS's own prompt, whose Open System Settings takes the user to the pane.
    func askMacOS() {
        try? keyValueStore.set(true, forKey: Self.askedKey)
        requestAccess()
    }

    /// Asks macOS first, so DuckDuckGo is listed in the Screen Recording pane even after it was removed
    /// from it; once the user has decided, asking is a no-op.
    func openSystemSettings() {
        requestAccess()
        openURL(.screenRecordingSystemSettings)
    }
}

/// Installs held back by Screen Recording: how many hit it, accept the alert, then capture.
protocol AIChatScreenshotPermissionInstrumentation {
    func permissionNeeded()
    func permissionAlertAccepted()
    func captureSucceeded()
}

final class DefaultAIChatScreenshotPermissionInstrumentation: AIChatScreenshotPermissionInstrumentation {

    private static let neededKey = "aichat.screenshot.permission-needed"

    private let pixelFiring: PixelFiring?
    private let keyValueStore: ThrowingKeyValueStoring

    init(pixelFiring: PixelFiring? = PixelKit.shared, keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.pixelFiring = pixelFiring
        self.keyValueStore = keyValueStore
    }

    /// Remembered across launches: macOS relaunches the app once Screen Recording is turned on.
    func permissionNeeded() {
        try? keyValueStore.set(true, forKey: Self.neededKey)
        pixelFiring?.fire(AIChatPixel.aiChatScreenshotPermissionNeeded, frequency: .uniqueByName)
    }

    func permissionAlertAccepted() {
        pixelFiring?.fire(AIChatPixel.aiChatScreenshotPermissionAlertAccepted, frequency: .uniqueByName)
    }

    /// Only installs that once hit the permission count, so converted over needed is the funnel's conversion.
    func captureSucceeded() {
        guard (try? keyValueStore.object(forKey: Self.neededKey)) as? Bool == true else { return }
        pixelFiring?.fire(AIChatPixel.aiChatScreenshotPermissionConverted, frequency: .uniqueByName)
    }
}
