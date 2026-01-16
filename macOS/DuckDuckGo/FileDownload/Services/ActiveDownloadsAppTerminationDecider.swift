//
//  ActiveDownloadsAppTerminationDecider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import Foundation

/// Handles active downloads during app termination.
/// Prompts user if there are active downloads and waits for their decision.
@MainActor
struct ActiveDownloadsAppTerminationDecider: ApplicationTerminationDecider {
    let downloadManager: FileDownloadManagerProtocol
    let downloadListCoordinator: DownloadListCoordinator

    func shouldTerminate(isAsync: Bool) -> TerminationQuery {
        guard !downloadManager.downloads.isEmpty else {
            return .sync(.next)
        }

        // if there're downloads without location chosen yet (save dialog should display) - cancel them
        let activeDownloads = Set(downloadManager.downloads.filter { $0.state.isDownloading })
        guard !activeDownloads.isEmpty else {
            // Cancel .initial state downloads
            return .async(Task { @MainActor in
                await downloadManager.cancelAll()
                await downloadListCoordinator.sync()
                return .next // Continue termination
            })
        }

        // Show modal alert for active downloads
        return .async(Task { @MainActor in
            let alert = NSAlert.activeDownloadsTerminationAlert(for: downloadManager.downloads)

            // Observe downloads finishing to auto-dismiss alert
            let downloadsFinishedCancellable = FileDownloadManager.observeDownloadsFinished(activeDownloads) {
                // close alert and quit when all downloads finished
                NSApp.stopModal(withCode: .OK)
            }

            let response = await alert.runModal()
            downloadsFinishedCancellable.cancel()

            if response == .cancel {
                return .cancel
            }

            // User chose to quit - cancel all downloads and wait
            await downloadManager.cancelAll()
            await downloadListCoordinator.sync()

            return .next // Continue termination
        })
    }
}
