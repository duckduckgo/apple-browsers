//
//  DownloadableLocalModelLifecycle.swift
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
import UIKit

/// What the downloadable model needs from the app on iOS, on top of the shared service. iOS suspends
/// an app soon after it leaves the screen, and ends suspended apps that use a lot of memory first.
///
/// Coming back needs nothing here: the service resumes a paused download when the app becomes active.
@MainActor
public final class DownloadableLocalModelLifecycle {

    static let backgroundTaskName = "LocalModelDownload"

    private let installer: AIChatLocalModelInstalling
    private let unloadModel: () -> Void
    private let openRuntime: () -> Void
    private let backgroundTasks: BackgroundTaskRunning
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - unloadModel: Frees the model's memory once any run in progress ends.
    ///   - openRuntime: Opens llama.cpp without loading the model.
    init(installer: AIChatLocalModelInstalling,
         unloadModel: @escaping () -> Void,
         openRuntime: @escaping () -> Void,
         backgroundTasks: BackgroundTaskRunning = ApplicationBackgroundTaskRunner(),
         notificationCenter: NotificationCenter = .default) {
        self.installer = installer
        self.unloadModel = unloadModel
        self.openRuntime = openRuntime
        self.backgroundTasks = backgroundTasks

        notificationCenter.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.didEnterBackground() }
            .store(in: &cancellables)

        notificationCenter.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.endBackgroundTask() }
            .store(in: &cancellables)

        installer.statePublisher
            .scan((previous: AIChatLocalModelInstallState?.none, current: AIChatLocalModelInstallState?.none)) { ($0.current, $1) }
            .sink { [weak self] states in self?.installStateChanged(from: states.previous, to: states.current) }
            .store(in: &cancellables)
    }

    private func didEnterBackground() {
        // About 700 MB in a suspended app would make it one of the first iOS ends. Loading it again takes under a second.
        // A summary in progress keeps the model until it ends: it pauses with the app and finishes when the app
        // is back, which on an iPhone beat stopping it and losing the summary.
        unloadModel()

        guard installer.isActive, backgroundTask == .invalid else { return }
        // The download gets the extra time iOS allows. Pausing before the app is suspended keeps the
        // dropped connection from counting as a failed attempt.
        backgroundTask = backgroundTasks.beginBackgroundTask(withName: Self.backgroundTaskName) { [weak self] in
            self?.installer.pause()
            self?.endBackgroundTask()
        }
    }

    private func installStateChanged(from previous: AIChatLocalModelInstallState?, to current: AIChatLocalModelInstallState?) {
        guard previous?.isDownloading == true, current?.isDownloading == false else { return }
        endBackgroundTask()
        // The first open on a device compiles llama.cpp's GPU code, which took 18 s on an iPhone.
        // Doing it now keeps that wait off the first summary.
        if current?.isInstalled == true {
            openRuntime()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        backgroundTasks.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
