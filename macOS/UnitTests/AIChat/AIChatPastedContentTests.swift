//
//  AIChatPastedContentTests.swift
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

@Suite("Duck.ai pasted content")
struct AIChatPastedContentTests {

    private static let png: Data = {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }()

    /// A private pasteboard, so the tests never touch the user's clipboard.
    private func makePasteboard(_ write: (NSPasteboardItem) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let item = NSPasteboardItem()
        write(item)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return pasteboard
    }

    @available(macOS 13, *)
    @Test("Finder copy attaches the file, not its icon or name", .timeLimit(.minutes(1)))
    func finderCopyAttachesTheFileNotItsIcon() {
        let pasteboard = makePasteboard {
            $0.setString(URL(fileURLWithPath: "/tmp/photo.png").absoluteString, forType: .fileURL)
            $0.setString("photo.png", forType: .string)
            $0.setData(Self.png, forType: .png)
        }
        defer { pasteboard.releaseGlobally() }

        guard case .files(let urls) = AIChatPastedContent.read(from: pasteboard) else {
            Issue.record("expected files")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["photo.png"])
    }

    @available(macOS 13, *)
    @Test("A copied file that can't be attached pastes its name", .timeLimit(.minutes(1)))
    func unattachableFileFallsThroughToText() {
        let pasteboard = makePasteboard {
            $0.setString(URL(fileURLWithPath: "/tmp/notes.txt").absoluteString, forType: .fileURL)
            $0.setString("notes.txt", forType: .string)
            $0.setData(Self.png, forType: .png)
        }
        defer { pasteboard.releaseGlobally() }

        #expect(AIChatPastedContent.read(from: pasteboard) == nil)
    }

    @available(macOS 13, *)
    @Test("Text wins over image data", .timeLimit(.minutes(1)))
    func textWinsOverImageData() {
        let pasteboard = makePasteboard {
            $0.setString("Quarterly numbers", forType: .string)
            $0.setData(Self.png, forType: .png)
        }
        defer { pasteboard.releaseGlobally() }

        #expect(AIChatPastedContent.read(from: pasteboard) == nil)
    }

    @available(macOS 13, *)
    @Test("Image data alone, or with blank text, attaches the image", .timeLimit(.minutes(1)), arguments: [nil, " \n"] as [String?])
    func imageDataAttaches(text: String?) {
        let pasteboard = makePasteboard {
            if let text { $0.setString(text, forType: .string) }
            $0.setData(Self.png, forType: .png)
        }
        defer { pasteboard.releaseGlobally() }

        guard case .image(let image) = AIChatPastedContent.read(from: pasteboard) else {
            Issue.record("expected an image")
            return
        }
        #expect(image.width == 4 && image.height == 2)
    }

    @available(macOS 13, *)
    @Test("Plain text pastes as text", .timeLimit(.minutes(1)))
    func plainTextIsANormalPaste() {
        let pasteboard = makePasteboard { $0.setString("hello", forType: .string) }
        defer { pasteboard.releaseGlobally() }

        #expect(AIChatPastedContent.read(from: pasteboard) == nil)
    }
}
