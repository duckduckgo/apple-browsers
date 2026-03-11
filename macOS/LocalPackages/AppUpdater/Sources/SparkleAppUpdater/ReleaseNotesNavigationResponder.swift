//
//  ReleaseNotesNavigationResponder.swift
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

import AppUpdaterShared
import BrowserServicesKit
import Combine
import Common
import Foundation
import Navigation
import WebKit

public struct ReleaseNotesValues: Codable {
    enum Status: String {
        case loaded
        case loading
        case loadingError
        case updateReady
        case updateDownloading
        case updatePreparing
        case updateError
        case criticalUpdateReady
    }

    let status: String
    let currentVersion: String
    let latestVersion: String?
    let lastUpdate: UInt
    let releaseTitle: String?
    let releaseNotes: [String]?
    let releaseNotesSubscription: [String]?
    let downloadProgress: Double?
    let automaticUpdate: Bool?
}

/// Sparkle-specific implementation of release notes navigation responder.
///
/// Handles displaying release notes, update progress, and triggering update checks
/// for the Sparkle update system.
public final class ReleaseNotesNavigationResponder: NavigationResponder {

    private var cancellables = Set<AnyCancellable>()
    private weak var webView: WKWebView? {
        didSet {
            releaseNotesUserScript?.webView = webView
        }
    }
    private weak var releaseNotesUserScript: ReleaseNotesUserScript?
    private let updateController: any SparkleUpdateControlling
    private let releaseNotesURL: URL

    public init(updateController: any SparkleUpdateControlling,
                releaseNotesURL: URL,
                scriptsPublisher: some Publisher<any ReleaseNotesUserScriptProvider, Never>,
                webViewPublisher: some Publisher<WKWebView, Never>) {
        self.updateController = updateController
        self.releaseNotesURL = releaseNotesURL

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            DispatchQueue.main.asyncOrNow {
                assert(scripts.releaseNotesUserScript == nil || scripts.releaseNotesUserScript is ReleaseNotesUserScript,
                       "Unexpected ReleaseNotesUserScript type: \(scripts.releaseNotesUserScript!)")
                self?.releaseNotesUserScript = scripts.releaseNotesUserScript as? ReleaseNotesUserScript
                self?.releaseNotesUserScript?.webView = self?.webView
                self?.setUpScript(for: self?.webView?.url)
            }
        }.store(in: &cancellables)
    }

    @MainActor
    public func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        if navigationAction.url == releaseNotesURL {
            return .allow
        }
        return .next
    }

    @MainActor
    private func setUpScript(for url: URL?) {
        guard AppVersion.runType != .uiTests else {
            return
        }
        Publishers.CombineLatest(updateController.updateProgressPublisher, updateController.latestUpdatePublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.releaseNotesUserScript?.onUpdate()
            }
            .store(in: &cancellables)
    }

    @MainActor
    public func navigationDidFinish(_ navigation: Navigation) {
        guard AppVersion.runType != .uiTests, navigation.url == releaseNotesURL else { return }
        if updateController.needsLatestReleaseNote {
            updateController.checkForUpdateSkippingRollout()
        }
    }
}

extension ReleaseNotesValues {

    init(status: Status,
         currentVersion: String,
         latestVersion: String? = nil,
         lastUpdate: UInt,
         releaseTitle: String? = nil,
         releaseNotes: [String]? = nil,
         releaseNotesSubscription: [String]? = nil,
         downloadProgress: Double? = nil,
         automaticUpdate: Bool?) {
        self.status = status.rawValue
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.lastUpdate = lastUpdate
        self.releaseTitle = releaseTitle
        self.releaseNotes = releaseNotes
        self.releaseNotesSubscription = releaseNotesSubscription
        self.downloadProgress = downloadProgress
        self.automaticUpdate = automaticUpdate
    }

    init(from updateController: any SparkleUpdateControlling) {
        let currentVersion = "\(AppVersion().versionNumber) (\(AppVersion().buildNumber))"
        let lastUpdate = UInt((updateController.lastUpdateCheckDate ?? Date()).timeIntervalSince1970)

        guard let latestUpdate = updateController.latestUpdate else {
            // When the update cycle is actively running we're still loading;
            // otherwise treat missing update info as a loading error.
            let status: Status = updateController.updateProgress.isIdle ? .loadingError : .loading
            self.init(status: status,
                      currentVersion: currentVersion,
                      lastUpdate: lastUpdate,
                      automaticUpdate: updateController.areAutomaticUpdatesEnabled)
            return
        }

        let updateState = UpdateState(from: updateController.latestUpdate, progress: updateController.updateProgress)

        let status: Status
        let downloadProgress: Double?
        switch updateState {
        case .upToDate:
            status = .loaded
            downloadProgress = nil
        case .updateCycle(let progress):
            if updateController.hasPendingUpdate {
                status = updateController.latestUpdate?.type == .critical ? .criticalUpdateReady : .updateReady
            } else {
                status = progress.toStatus
            }
            downloadProgress = progress.toDownloadProgress
        }

        let automaticUpdate = updateController.isAtRestartCheckpoint

        self.init(status: status,
                  currentVersion: currentVersion,
                  latestVersion: latestUpdate.versionString,
                  lastUpdate: lastUpdate,
                  releaseTitle: latestUpdate.title,
                  releaseNotes: latestUpdate.releaseNotes,
                  releaseNotesSubscription: latestUpdate.releaseNotesSubscription,
                  downloadProgress: downloadProgress,
                  automaticUpdate: automaticUpdate)
    }
}

private extension Update {
    var versionString: String? {
        "\(version) (\(build))"
    }
}

private extension UpdateCycleProgress {
    var toStatus: ReleaseNotesValues.Status {
        switch self {
        case .updateCycleDidStart: return .loading
        case .downloadDidStart, .downloading: return .updateDownloading
        case .extractionDidStart, .extracting, .readyToInstallAndRelaunch, .installationDidStart, .installing: return .updatePreparing
        case .updaterError: return .updateError
        case .updateCycleNotStarted, .updateCycleDone: return .loaded
        }
    }

    var toDownloadProgress: Double? {
        guard case .downloading(let percentage) = self else { return nil }
        return percentage
    }
}
