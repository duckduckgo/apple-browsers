//
//  DownloadableLocalModelLifecycleTests.swift
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

import AIChat
import Combine
import Foundation
import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
@Suite("Downloadable local model lifecycle")
final class DownloadableLocalModelLifecycleTests {

    private let installer = LifecycleInstaller()
    private let backgroundTasks = BackgroundTaskSpy()
    private let notificationCenter = NotificationCenter()
    private var unloadCount = 0
    private var openRuntimeCount = 0

    private func makeLifecycle() -> DownloadableLocalModelLifecycle {
        DownloadableLocalModelLifecycle(installer: installer,
                                        unloadModel: { [unowned self] in self.unloadCount += 1 },
                                        openRuntime: { [unowned self] in self.openRuntimeCount += 1 },
                                        backgroundTasks: backgroundTasks,
                                        notificationCenter: notificationCenter)
    }

    private func enterBackground() {
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaving the app frees the model's memory", .timeLimit(.minutes(1)))
    func backgroundUnloads() {
        let lifecycle = makeLifecycle()

        enterBackground()

        #expect(unloadCount == 1)
        #expect(backgroundTasks.begun.isEmpty)
        _ = lifecycle
    }

    private func startDownloading() {
        installer.state = .downloading(receivedBytes: 1, totalBytes: 10)
        installer.isActive = true
    }

    @available(iOS 16, macOS 13, *)
    @Test("A download keeps going in the background, and pauses when that time runs out", .timeLimit(.minutes(1)))
    func downloadPausesWhenBackgroundTimeRunsOut() {
        startDownloading()
        let lifecycle = makeLifecycle()

        enterBackground()
        #expect(backgroundTasks.begun == [DownloadableLocalModelLifecycle.backgroundTaskName])
        #expect(installer.pauseCount == 0)

        backgroundTasks.expire()

        #expect(installer.pauseCount == 1)
        #expect(backgroundTasks.ended.count == 1)
        _ = lifecycle
    }

    @available(iOS 16, macOS 13, *)
    @Test("Coming back ends the background time without pausing", .timeLimit(.minutes(1)))
    func comingBackEndsTheBackgroundTask() {
        startDownloading()
        let lifecycle = makeLifecycle()
        enterBackground()

        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        #expect(backgroundTasks.ended.count == 1)
        #expect(installer.pauseCount == 0)
        _ = lifecycle
    }

    @available(iOS 16, macOS 13, *)
    @Test("A finished download opens llama.cpp and ends the background time", .timeLimit(.minutes(1)))
    func finishedDownloadOpensTheRuntime() {
        startDownloading()
        let lifecycle = makeLifecycle()
        enterBackground()

        installer.state = .installed(URL(fileURLWithPath: "/model.gguf"))

        #expect(openRuntimeCount == 1)
        #expect(backgroundTasks.ended.count == 1)
        _ = lifecycle
    }

    @available(iOS 16, macOS 13, *)
    @Test("A paused download, or one waiting to retry, gets no background time", .timeLimit(.minutes(1)))
    func idleDownloadGetsNoBackgroundTime() {
        installer.state = .downloading(receivedBytes: 1, totalBytes: 10)
        installer.isActive = false
        let lifecycle = makeLifecycle()

        enterBackground()

        #expect(backgroundTasks.begun.isEmpty)
        _ = lifecycle
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed download, or a model installed before launch, doesn't open llama.cpp", .timeLimit(.minutes(1)))
    func onlyAFreshInstallOpensTheRuntime() {
        installer.state = .installed(URL(fileURLWithPath: "/model.gguf"))
        let installed = makeLifecycle()
        #expect(openRuntimeCount == 0)

        let failing = LifecycleInstaller()
        failing.state = .downloading(receivedBytes: 1, totalBytes: 10)
        let lifecycle = DownloadableLocalModelLifecycle(installer: failing,
                                                        unloadModel: {},
                                                        openRuntime: { [unowned self] in self.openRuntimeCount += 1 },
                                                        backgroundTasks: backgroundTasks,
                                                        notificationCenter: notificationCenter)
        failing.state = .failed(.network)

        #expect(openRuntimeCount == 0)
        _ = (installed, lifecycle)
    }
}

private final class LifecycleInstaller: AIChatLocalModelInstalling {
    let spec = AIChatLocalModelSpec.gemma4E2B
    var isActive = false
    private let subject = CurrentValueSubject<AIChatLocalModelInstallState, Never>(.notInstalled)
    private(set) var pauseCount = 0

    var state: AIChatLocalModelInstallState {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var statePublisher: AnyPublisher<AIChatLocalModelInstallState, Never> {
        subject.eraseToAnyPublisher()
    }

    func install() {}
    func cancel() {}
    func uninstall() {}
    func resumeIfNeeded() {}

    func pause() {
        pauseCount += 1
    }
}

@MainActor
private final class BackgroundTaskSpy: BackgroundTaskRunning {
    private(set) var begun: [String] = []
    private(set) var ended: [UIBackgroundTaskIdentifier] = []
    private var expirationHandler: (@MainActor () -> Void)?

    func beginBackgroundTask(withName name: String, expirationHandler: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier {
        begun.append(name)
        self.expirationHandler = expirationHandler
        return UIBackgroundTaskIdentifier(rawValue: begun.count)
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        ended.append(identifier)
    }

    func expire() {
        expirationHandler?()
    }
}
