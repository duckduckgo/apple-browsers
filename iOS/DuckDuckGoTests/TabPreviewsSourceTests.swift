//
//  TabPreviewsSourceTests.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import DuckDuckGo

class TabPreviewsSourceTests: XCTestCase {
    
    private static func makeContainerUrl() -> URL? {
        guard var cachesDirURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        cachesDirURL.appendPathComponent(UUID().uuidString, isDirectory: true)
        return cachesDirURL
    }
    
    private let containerUrl = TabPreviewsSourceTests.makeContainerUrl()
    
    override func setUp() {
        super.setUp()
        
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }
        
        do {
            try FileManager.default.createDirectory(at: containerUrl,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            XCTFail("Could not create test dir")
        }
    }
    
    override func tearDown() {
        super.tearDown()
        
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }
        
        do {
            try FileManager.default.removeItem(at: containerUrl)
        } catch {
            XCTFail("Could not cleanup test dir")
        }
    }
    
    func testWhenNothingToMigrateThenDoNothing() {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }
        
        let fromUrl = containerUrl.appendingPathComponent("src", isDirectory: true)
        let toUrl = containerUrl.appendingPathComponent("dst", isDirectory: true)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fromUrl.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: toUrl.path))
        
        let source = DefaultTabPreviewsSource(storeDir: toUrl, legacyDir: fromUrl)
        source.prepare()
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fromUrl.path))
        
        var isDir: ObjCBool = false
        XCTAssert(FileManager.default.fileExists(atPath: toUrl.path, isDirectory: &isDir))
        XCTAssert(isDir.boolValue)
    }
    
    func testWhenEmptySourceToMigrateThenJustRemoveIt() {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }
        
        let fromUrl = containerUrl.appendingPathComponent("src", isDirectory: true)
        let toUrl = containerUrl.appendingPathComponent("dst", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: fromUrl,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        } catch {
            XCTFail("Could not prepare source directory")
        }
        
        var isDir: ObjCBool = false
        
        XCTAssert(FileManager.default.fileExists(atPath: fromUrl.path, isDirectory: &isDir))
        XCTAssert(isDir.boolValue)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: toUrl.path))
        
        let source = DefaultTabPreviewsSource(storeDir: toUrl, legacyDir: fromUrl)
        source.prepare()
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fromUrl.path))

        XCTAssert(FileManager.default.fileExists(atPath: toUrl.path, isDirectory: &isDir))
        XCTAssert(isDir.boolValue)
    }
    
    func testWhenMigratingThenPreviewsAreCopiedAndSourceIsRemoved() {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }
        
        let fromUrl = containerUrl.appendingPathComponent("src", isDirectory: true)
        let toUrl = containerUrl.appendingPathComponent("dst", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: fromUrl,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
            
            // Prepare png file
            let pngFile = fromUrl.appendingPathComponent("test.png")
            try "".write(to: pngFile, atomically: false, encoding: .utf8)
            
            // Prepare random file
            let randomFile = fromUrl.appendingPathComponent("test.file")
            try "".write(to: randomFile, atomically: false, encoding: .utf8)
        } catch {
            XCTFail("Could not prepare source directory")
        }
        
        var isDir: ObjCBool = false
        
        XCTAssert(FileManager.default.fileExists(atPath: fromUrl.path, isDirectory: &isDir))
        XCTAssert(isDir.boolValue)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: toUrl.path))
        
        let source = DefaultTabPreviewsSource(storeDir: toUrl, legacyDir: fromUrl)
        source.prepare()
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fromUrl.path))

        XCTAssert(FileManager.default.fileExists(atPath: toUrl.path, isDirectory: &isDir))
        XCTAssert(isDir.boolValue)
        
        let pngFile = toUrl.appendingPathComponent("test.png")
        XCTAssert(FileManager.default.fileExists(atPath: pngFile.path))
        let testFile = toUrl.appendingPathComponent("test.file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))
    }
    
    func testWhenStoreDirCreatedThenItIsNotBackedUp() {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }
        
        let fromUrl = containerUrl.appendingPathComponent("src", isDirectory: true)
        let toUrl = containerUrl.appendingPathComponent("dst", isDirectory: true)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: toUrl.path))
        
        let source = DefaultTabPreviewsSource(storeDir: toUrl, legacyDir: fromUrl)
        source.prepare()
        
        var isDir: ObjCBool = false
        XCTAssert(FileManager.default.fileExists(atPath: toUrl.path, isDirectory: &isDir))
        XCTAssert(isDir.boolValue)
        
        do {
            var storeUrl = toUrl
            storeUrl.removeAllCachedResourceValues()
            let values = try storeUrl.resourceValues(forKeys: [URLResourceKey.isExcludedFromBackupKey])
            
            XCTAssert(values.isExcludedFromBackup ?? false)
        } catch {
            XCTFail("Could not determine resource values")
        }
    }
    
    func testWhenExcessPreviewsExistThenTheseAreRemoved() async {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }
        
        let storeURL = containerUrl.appendingPathComponent("src", isDirectory: true)
        let legacyURL = containerUrl.appendingPathComponent("oldsrc", isDirectory: true)
        
        let source = DefaultTabPreviewsSource(storeDir: storeURL, legacyDir: legacyURL)
        source.prepare()
        _ = source.removeAllPreviews()

        do {
            let storeBlock: (String) throws -> Void = { name in
                let pngFile = storeURL.appendingPathComponent("\(name).png")
                try "".write(to: pngFile, atomically: false, encoding: .utf8)
            }
            
            // Prepare valid files
            try storeBlock("v1")
            try storeBlock("v2")
            
            // Prepare invalid files
            try storeBlock("v3")
            try storeBlock("v4")
            
        } catch {
            XCTFail("Could not prepare source directory")
        }
        
        var isDir: ObjCBool = false
        
        XCTAssert(FileManager.default.fileExists(atPath: storeURL.path, isDirectory: &isDir))
        XCTAssert(isDir.boolValue)
        
        let contents = pngFiles(in: storeURL)
        XCTAssertEqual(contents.count, 4)

        await source.removePreviewsWithIdNotIn([ "v1", "v2" ])

        let newContents = pngFiles(in: storeURL)
        XCTAssertEqual(newContents.count, 2)
        XCTAssertEqual(newContents.contains("v1.png"), true)
        XCTAssertEqual(newContents.contains("v2.png"), true)
    }

    // MARK: - Full-screen snapshot lifecycle

    func testWhenRemovePreviewForTabThenFullScreenSnapshotAlsoRemoved() {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }

        let storeURL = containerUrl.appendingPathComponent("src", isDirectory: true)
        let legacyURL = containerUrl.appendingPathComponent("oldsrc", isDirectory: true)
        let source = DefaultTabPreviewsSource(storeDir: storeURL, legacyDir: legacyURL)
        source.prepare()

        let tab = Tab(uid: "v1", fireTab: false)
        seedFullScreenJPEG(uid: "v1", in: storeURL)
        seedPNG(uid: "v1", in: storeURL)

        let jpegURL = fullScreenJPEGURL(uid: "v1", in: storeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpegURL.path))

        source.removePreview(forTab: tab)

        waitUntilGone(jpegURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: jpegURL.path))
    }

    func testWhenRemoveAllPreviewsThenFullScreenSnapshotsAlsoRemoved() {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }

        let storeURL = containerUrl.appendingPathComponent("src", isDirectory: true)
        let legacyURL = containerUrl.appendingPathComponent("oldsrc", isDirectory: true)
        let source = DefaultTabPreviewsSource(storeDir: storeURL, legacyDir: legacyURL)
        source.prepare()

        seedFullScreenJPEG(uid: "v1", in: storeURL)
        seedFullScreenJPEG(uid: "v2", in: storeURL)
        seedPNG(uid: "v1", in: storeURL)

        let fullScreenDir = storeURL.appendingPathComponent("FullScreen", isDirectory: true)
        let existingJPEGs = try? FileManager.default.contentsOfDirectory(atPath: fullScreenDir.path)
        XCTAssertEqual(existingJPEGs?.count, 2)

        _ = source.removeAllPreviews()

        // `removeAllPreviews` deletes the FullScreen subdirectory recursively (synchronously)
        // and then recreates it empty.
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: fullScreenDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        let remainingJPEGs = try? FileManager.default.contentsOfDirectory(atPath: fullScreenDir.path)
        XCTAssertEqual(remainingJPEGs?.count, 0)
        XCTAssertEqual(pngFiles(in: storeURL).count, 0)
    }

    func testWhenRemovePreviewsWithIdNotInThenOrphanFullScreenSnapshotsAreRemoved() async {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }

        let storeURL = containerUrl.appendingPathComponent("src", isDirectory: true)
        let legacyURL = containerUrl.appendingPathComponent("oldsrc", isDirectory: true)
        let source = DefaultTabPreviewsSource(storeDir: storeURL, legacyDir: legacyURL)
        source.prepare()

        seedFullScreenJPEG(uid: "v1", in: storeURL)
        seedFullScreenJPEG(uid: "v2", in: storeURL)
        seedFullScreenJPEG(uid: "v3", in: storeURL)
        seedPNG(uid: "v1", in: storeURL)
        seedPNG(uid: "v2", in: storeURL)
        seedPNG(uid: "v3", in: storeURL)

        _ = source.removePreviewsWithIdNotIn(["v1", "v2"])

        let v3JPEG = fullScreenJPEGURL(uid: "v3", in: storeURL)
        waitUntilGone(v3JPEG)

        let v1JPEG = fullScreenJPEGURL(uid: "v1", in: storeURL)
        let v2JPEG = fullScreenJPEGURL(uid: "v2", in: storeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: v1JPEG.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: v2JPEG.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: v3JPEG.path))

        let remainingPNGs = pngFiles(in: storeURL)
        XCTAssertEqual(remainingPNGs.count, 2)
        XCTAssertTrue(remainingPNGs.contains("v1.png"))
        XCTAssertTrue(remainingPNGs.contains("v2.png"))
    }

    func testWhenUpdateFullScreenSnapshotThenItCanBeRetrieved() {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }

        let storeURL = containerUrl.appendingPathComponent("src", isDirectory: true)
        let legacyURL = containerUrl.appendingPathComponent("oldsrc", isDirectory: true)
        let source = DefaultTabPreviewsSource(storeDir: storeURL, legacyDir: legacyURL)
        source.prepare()

        let tab = Tab(uid: "v1", fireTab: false)
        let image = makeSolidColorImage()
        source.updateFullScreenSnapshot(image, forTab: tab)

        // Hits the in-memory cache — disk write is async but cache is synchronous.
        XCTAssertNotNil(source.fullScreenSnapshot(for: tab))
    }

    func testWhenNoFullScreenSnapshotExistsThenNilIsReturned() {
        guard let containerUrl = containerUrl else {
            XCTFail("Could not determine containerUrl")
            return
        }

        let storeURL = containerUrl.appendingPathComponent("src", isDirectory: true)
        let legacyURL = containerUrl.appendingPathComponent("oldsrc", isDirectory: true)
        let source = DefaultTabPreviewsSource(storeDir: storeURL, legacyDir: legacyURL)
        source.prepare()

        let tab = Tab(uid: "missing", fireTab: false)
        XCTAssertNil(source.fullScreenSnapshot(for: tab))
    }

    // MARK: - Helpers

    private func pngFiles(in directory: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return entries.filter { $0.hasSuffix(".png") }
    }

    private func fullScreenJPEGURL(uid: String, in storeURL: URL) -> URL {
        storeURL.appendingPathComponent("FullScreen", isDirectory: true).appendingPathComponent("\(uid).jpg")
    }

    private func seedFullScreenJPEG(uid: String, in storeURL: URL) {
        let dir = storeURL.appendingPathComponent("FullScreen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let url = dir.appendingPathComponent("\(uid).jpg")
        do {
            try "".write(to: url, atomically: false, encoding: .utf8)
        } catch {
            XCTFail("Could not seed JPEG \(uid): \(error)")
        }
    }

    private func seedPNG(uid: String, in storeURL: URL) {
        let url = storeURL.appendingPathComponent("\(uid).png")
        do {
            try "".write(to: url, atomically: false, encoding: .utf8)
        } catch {
            XCTFail("Could not seed PNG \(uid): \(error)")
        }
    }

    private func makeSolidColorImage() -> UIImage {
        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Polls until the given URL no longer exists. JPEG removal is dispatched to a
    /// background utility queue, so the file may persist a few ticks after the API call.
    /// `XCTNSPredicateExpectation` defaults to a 1s polling interval, which is too coarse
    /// for sub-second async file ops — runloop-pump on a tight interval instead.
    private func waitUntilGone(_ url: URL, timeout: TimeInterval = 2.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !FileManager.default.fileExists(atPath: url.path) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("File was not removed within \(timeout)s: \(url.path)")
    }
}
