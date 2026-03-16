//
//  SandboxTestTool.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import AppKitExtensions
import Combine
import Common
import Foundation
import os.log
import SharedSandboxTestUtilities

@main
struct SandboxTestTool {
    static func main() {
        SandboxTestToolApp.shared.run()
    }
}

@objc(SandboxTestToolApp)
final class SandboxTestToolApp: NSApplication {

    private var _delegate: SandboxTestToolAppDelegate! // swiftlint:disable:this weak_delegate

    override init() {
        // swizzle `startAccessingSecurityScopedResource` and `stopAccessingSecurityScopedResource`
        // methods to accurately reflect the current number of start and stop calls
        // stored in the associated `NSURL.sandboxExtensionRetainCount` value.
        //
        // See SecurityScopedFileURLController.swift
        NSURL.swizzleStartStopAccessingSecurityScopedResourceOnce()

        super.init()

        // Keep the helper out of the active app cycle so browser tests do not depend on app focus.
        setActivationPolicy(.prohibited)

        _delegate = SandboxTestToolAppDelegate()
        self.delegate = _delegate
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

final class SandboxTestToolAppDelegate: NSObject, NSApplicationDelegate {

    let logger = Logger(subsystem: "SandboxTestTool", category: "")

    override init() {
        logger.log("\n\n\n🚦 starting…\n")

        super.init()

        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(terminate(_:)), name: SandboxTestNotification.terminate.name, object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(ping(_:)), name: SandboxTestNotification.ping.name, object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(openFile(_:)), name: SandboxTestNotification.openFile.name, object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(openFile(_:)), name: SandboxTestNotification.openFileWithoutBookmark.name, object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(openBookmarkWithFilePresenter(_:)), name: SandboxTestNotification.openBookmarkWithFilePresenter.name, object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(closeFilePresenter(_:)), name: SandboxTestNotification.closeFilePresenter.name, object: nil, suspensionBehavior: .deliverImmediately)

        NSURL.swizzleStopAccessingSecurityScopedResource { [unowned self] url in
            post(.stopAccessingSecurityScopedResourceCalled, with: url.path)
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        post(.hello, with: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.log("🚦 didFinishLaunching\n")
    }

    @objc private func ping(_ notification: Notification) {
        logger.log("➡️  ping")
        post(.pong, with: notification.object as? String)
    }

    @objc private func openFile(_ notification: Notification) {
        logger.log("➡️  openFile \(notification.object as? String ?? "<nil>")")
        guard let filePath = notification.object as? String else {
            post(.error, with: "No file path provided")
            return
        }
        openFile(filePath, creatingBookmark: notification.name == SandboxTestNotification.openFile)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        logger.log("➡️  app.openFile(\"\(filename)\")")
        openFile(filename, creatingBookmark: true)
        return true
    }

    private func openFile(_ filePath: String, creatingBookmark bookmarkNeeded: Bool) {
        let url = URL(fileURLWithPath: filePath)

        let data: String
        do {
            data = try String(contentsOf: url)
        } catch {
            post(.error, with: error.encoded("Error opening file"))
            return
        }

        var bookmark: Data?
        if bookmarkNeeded {
            do {
                bookmark = try url.bookmarkData(options: .withSecurityScope)
            } catch let error as NSError {
                post(.error, with: error.encoded("Error creating bookmark"))
                return
            }
        }

        post(.fileRead, with: FileReadResult(path: filePath, data: data, bookmark: bookmark).encoded())
    }

    private var filePresenters = [URL: FilePresenter]()
    private var filePresenterCancellables = [URL: Set<AnyCancellable>]()

    @objc private func openBookmarkWithFilePresenter(_ notification: Notification) {
        logger.log("📕 openBookmarkWithFilePresenter")
        guard let object = notification.object as? String, let bookmark = Data(base64Encoded: object) else {
            post(.error, with: CocoaError(CocoaError.Code.coderReadCorrupt).encoded("Invalid bookmark data"))
            return
        }
        do {
            let filePresenter = try BookmarkFilePresenter(fileBookmarkData: bookmark)
            guard let url = filePresenter.url else { throw NSError(domain: "SandboxTestTool", code: -1, userInfo: [NSLocalizedDescriptionKey: "FilePresenter URL is nil"]) }

            filePresenter.urlPublisher.dropFirst().sink { [unowned self] url in
                post(.fileMoved, with: url?.path)
            }.store(in: &filePresenterCancellables[url, default: []])
            filePresenter.fileBookmarkDataPublisher.dropFirst().sink { [unowned self] fileBookmarkData in
                post(.fileBookmarkDataUpdated, with: fileBookmarkData?.base64EncodedString())
            }.store(in: &filePresenterCancellables[url, default: []])
            self.filePresenters[url] = filePresenter
            logger.log("📗 openBookmarkWithFilePresenter done: \"\(filePresenter.url?.path ?? "<nil>")\"")
        } catch {
            post(.error, with: error.encoded("could not open BookmarkFilePresenter"))
        }
    }

    @objc private func closeFilePresenter(_ notification: Notification) {
        guard let path = notification.object as? String else {
            post(.error, with: CocoaError(CocoaError.Code.coderReadCorrupt).encoded("Should provide file path to close Presenter"))
            return
        }
        logger.log("🌂 closeFilePresenter for \(path)")
        let url = URL(fileURLWithPath: path)
        filePresenterCancellables[url] = nil
        filePresenters[url] = nil
    }

    @objc private func terminate(_ notification: Notification) {
        logger.log("😵 terminate\n---------------")
        NSApp.terminate(self)
    }

    private func post(_ name: SandboxTestNotification, with object: String? = nil) {
        logger.log("📮 \(name.rawValue)\(object != nil ? ": \(object!)" : "")")
        DistributedNotificationCenter.default().postNotificationName(.init(name.rawValue), object: object, userInfo: nil, deliverImmediately: true)
    }

}

private extension Error {
    func encoded(_ descr: String? = nil, file: StaticString = #file, line: UInt = #line) -> String {
        let error = self as NSError
        var dict: [String: Any] = [
            UserInfoKeys.errorDomain: error.domain,
            UserInfoKeys.errorCode: error.code
        ].merging(error.userInfo.filter { $0.value is String || $0.value is Int }, uniquingKeysWith: { $1 })
        if let descr {
            dict[UserInfoKeys.errorDescription] = descr
        }
        let json = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        return String(data: json!, encoding: .utf8)!
    }
}

extension NSURL {

    private static var stopAccessingSecurityScopedResourceCallback: ((URL) -> Void)?

    private static let originalStopAccessingSecurityScopedResource = {
        class_getInstanceMethod(NSURL.self, #selector(NSURL.stopAccessingSecurityScopedResource))!
    }()
    private static let swizzledStopAccessingSecurityScopedResource = {
        class_getInstanceMethod(NSURL.self, #selector(NSURL.test_tool_stopAccessingSecurityScopedResource))!
    }()
    private static let swizzleStopAccessingSecurityScopedResourceOnce: Void = {
        method_exchangeImplementations(originalStopAccessingSecurityScopedResource, swizzledStopAccessingSecurityScopedResource)
    }()

    static func swizzleStopAccessingSecurityScopedResource(with stopAccessingSecurityScopedResourceCallback: ((URL) -> Void)?) {
        _=swizzleStopAccessingSecurityScopedResourceOnce
        self.stopAccessingSecurityScopedResourceCallback = stopAccessingSecurityScopedResourceCallback
    }

    @objc private dynamic func test_tool_stopAccessingSecurityScopedResource() {
        if let stopAccessingSecurityScopedResourceCallback = Self.stopAccessingSecurityScopedResourceCallback {
            stopAccessingSecurityScopedResourceCallback(self as URL)
        }
        self.test_tool_stopAccessingSecurityScopedResource() // call original
    }

}
