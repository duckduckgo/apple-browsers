//
//  AIChatScreenshotCaptureTests.swift
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
import Testing
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 13, *)
@Suite("Duck.ai screenshot capture")
struct AIChatScreenshotCaptureTests {

    // MARK: - Image processing

    @Test("The long side is capped at 1024 px and the aspect ratio kept", .timeLimit(.minutes(1)))
    func scaledSizeCapsLongSide() {
        let wide = AIChatScreenshotImageProcessor.scaledSize(width: 2048, height: 1000)
        #expect(wide.width == 1024)
        #expect(wide.height == 500)

        let tall = AIChatScreenshotImageProcessor.scaledSize(width: 1000, height: 3000)
        #expect(tall.width == 341)
        #expect(tall.height == 1024)
    }

    @Test("A capture already within 1024 px is never upscaled", .timeLimit(.minutes(1)))
    func scaledSizeNeverUpscales() {
        let size = AIChatScreenshotImageProcessor.scaledSize(width: 800, height: 600)
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test("A plain capture is sent as PNG at its own size", .timeLimit(.minutes(1)))
    func smallCaptureStaysPNG() throws {
        let image = try makeImage(width: 640, height: 480, noise: false)
        let processed = try #require(AIChatScreenshotImageProcessor.process(image, kind: .window))
        #expect(processed.format == .png)
        #expect(processed.image.width == 640)
        #expect(processed.image.height == 480)
        #expect(processed.kind == .window)
    }

    @Test("A capture whose PNG exceeds 2 MiB falls back to JPEG", .timeLimit(.minutes(1)))
    func largePNGFallsBackToJPEG() throws {
        // Noise doesn't compress: 1024×1024 RGB is ~3 MB as PNG.
        let image = try makeImage(width: 1024, height: 1024, noise: true)
        let processed = try #require(AIChatScreenshotImageProcessor.process(image, kind: .selection))
        #expect(processed.format == .jpeg)
        #expect(processed.image.width == 1024)
    }

    // MARK: - Region selection

    @Test("A drag past the screen edge is clamped to the screen it started on", .timeLimit(.minutes(1)))
    func regionRectClampsToBounds() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = try #require(AIChatRegionSelection.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 2000, y: -50), in: bounds))
        #expect(rect == CGRect(x: 100, y: 0, width: 1340, height: 100))
    }

    @Test("A drag smaller than 4 pt is a click, not a selection", .timeLimit(.minutes(1)))
    func tinyDragIsNotASelection() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(AIChatRegionSelection.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 13, y: 40), in: bounds) == nil)
    }

    @Test("At 2× the crop is the selection in pixels, flipped to a top-left origin", .timeLimit(.minutes(1)))
    func pixelRectAt2x() {
        let pixels = AIChatRegionSelection.pixelRect(for: CGRect(x: 10, y: 20, width: 100, height: 50),
                                                     viewSize: CGSize(width: 1440, height: 900),
                                                     imageWidth: 2880,
                                                     imageHeight: 1800)
        #expect(pixels == CGRect(x: 20, y: 1660, width: 200, height: 100))
    }

    @Test("At a scaled 1.5× display the crop still matches the selection", .timeLimit(.minutes(1)))
    func pixelRectAtFractionalScale() {
        let pixels = AIChatRegionSelection.pixelRect(for: CGRect(x: 10, y: 10, width: 100, height: 100),
                                                     viewSize: CGSize(width: 1920, height: 1080),
                                                     imageWidth: 2880,
                                                     imageHeight: 1620)
        #expect(pixels == CGRect(x: 15, y: 1455, width: 150, height: 150))
    }

    // MARK: - Screen Recording permission

    @Test("The system prompt is raised once; every later denial shows the explainer", .timeLimit(.minutes(1)))
    func permissionPromptsOnceThenExplains() throws {
        let defaults = try #require(UserDefaults(suiteName: "AIChatScreenshotCaptureTests.\(UUID().uuidString)"))
        var requests = 0
        let permission = AIChatScreenRecordingPermission(isGranted: { false }, requestAccess: { requests += 1 }, userDefaults: defaults)

        #expect(permission.resolve() == .requestedSystemPrompt)
        #expect(permission.resolve() == .deniedShowExplainer)
        #expect(permission.resolve() == .deniedShowExplainer)
        #expect(requests == 1)
    }

    @Test("Open System Settings asks macOS first, so the app is listed in the pane", .timeLimit(.minutes(1)))
    func openSystemSettingsRequestsThenOpensPane() {
        var events: [String] = []
        let permission = AIChatScreenRecordingPermission(isGranted: { false },
                                                         requestAccess: { events.append("request") },
                                                         openURL: { events.append($0.absoluteString) })
        permission.openSystemSettings()
        #expect(events == ["request", URL.screenRecordingSystemSettings.absoluteString])
    }

    @Test("Granted permission never prompts", .timeLimit(.minutes(1)))
    func grantedPermissionNeverPrompts() throws {
        let defaults = try #require(UserDefaults(suiteName: "AIChatScreenshotCaptureTests.\(UUID().uuidString)"))
        var requests = 0
        let permission = AIChatScreenRecordingPermission(isGranted: { true }, requestAccess: { requests += 1 }, userDefaults: defaults)

        #expect(permission.resolve() == .granted)
        #expect(requests == 0)
    }

    // MARK: - Helpers

    private func makeImage(width: Int, height: Int, noise: Bool) throws -> CGImage {
        let context = try #require(CGContext(data: nil,
                                             width: width,
                                             height: height,
                                             bitsPerComponent: 8,
                                             bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if noise, let data = context.data {
            let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
            for index in 0..<(width * height * 4) {
                bytes[index] = index % 4 == 3 ? 255 : UInt8.random(in: 0...255)
            }
        } else {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(context.makeImage())
    }
}
