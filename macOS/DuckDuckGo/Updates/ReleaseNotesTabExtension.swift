//
//  ReleaseNotesTabExtension.swift
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import Navigation
import PixelKit
import WebKit

#if SPARKLE

protocol ReleaseNotesUserScriptProvider {

    var releaseNotesUserScript: ReleaseNotesUserScript? { get }

}

extension UserScripts: ReleaseNotesUserScriptProvider {}

public struct ReleaseNotesValues: Codable {
    enum Status: String {
        case loaded
        case loading
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
    let releaseNotesPrivacyPro: [String]?
    let downloadProgress: Double?
    let automaticUpdate: Bool?
}

final class ReleaseNotesTabExtension: NavigationResponder {

    private var cancellables = Set<AnyCancellable>()
    private weak var webView: WKWebView? {
        didSet {
            releaseNotesUserScript?.webView = webView
        }
    }
    private weak var releaseNotesUserScript: ReleaseNotesUserScript?

    init(scriptsPublisher: some Publisher<some ReleaseNotesUserScriptProvider, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>) {

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            self?.releaseNotesUserScript = scripts.releaseNotesUserScript
            self?.releaseNotesUserScript?.webView = self?.webView

            DispatchQueue.main.async { [weak self] in
                self?.setUpScript(for: self?.webView?.url)
            }
        }.store(in: &cancellables)
    }

    @MainActor
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        if navigationAction.url == .releaseNotes {
            return .allow
        }
        return .next
    }

    @MainActor
    private func setUpScript(for url: URL?) {
        guard AppVersion.runType != .uiTests else {
            return
        }
        let updateController = Application.appDelegate.updateController!
        Publishers.CombineLatest(updateController.updateProgressPublisher, updateController.latestUpdatePublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.releaseNotesUserScript?.onUpdate()
            }
            .store(in: &cancellables)
    }

    @MainActor
    func navigationDidFinish(_ navigation: Navigation) {
        guard AppVersion.runType != .uiTests, navigation.url == .releaseNotes else { return }
        let updateController = Application.appDelegate.updateController!
        if updateController.latestUpdate?.needsLatestReleaseNote == true {
            updateController.checkForUpdateSkippingRollout()
        }
    }
}

protocol ReleaseNotesTabExtensionProtocol: AnyObject, NavigationResponder {}

extension ReleaseNotesTabExtension: ReleaseNotesTabExtensionProtocol, TabExtension {
    func getPublicProtocol() -> ReleaseNotesTabExtensionProtocol { self }
}

extension TabExtensions {
    var releaseNotes: ReleaseNotesTabExtensionProtocol? { resolve(ReleaseNotesTabExtension.self) }
}

extension ReleaseNotesValues {

    init(status: Status,
         currentVersion: String,
         latestVersion: String? = nil,
         lastUpdate: UInt,
         releaseTitle: String? = nil,
         releaseNotes: [String]? = nil,
         releaseNotesPrivacyPro: [String]? = nil,
         downloadProgress: Double? = nil,
         automaticUpdate: Bool?) {
        self.status = status.rawValue
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.lastUpdate = lastUpdate
        self.releaseTitle = releaseTitle
        self.releaseNotes = releaseNotes
        self.releaseNotesPrivacyPro = releaseNotesPrivacyPro
        self.downloadProgress = downloadProgress
        self.automaticUpdate = automaticUpdate
    }

    init(from updateController: UpdateController, pixelKit: PixelKit? = PixelKit.shared) {
        let currentVersion = "\(AppVersion().versionNumber) (\(AppVersion().buildNumber))"
        let lastUpdate = UInt((updateController.lastUpdateCheckDate ?? Date()).timeIntervalSince1970)

        // Fall back to cached release notes if necessary
        // This happens when there's no connectivity,
        // or when the appcast hasn't finished loading by the time the Release Notes screen shows up
        guard let latestUpdate = updateController.latestUpdate else {
            let keyValueStore = Application.appDelegate.keyValueStore
            if let data = try? keyValueStore.object(forKey: UpdateController.Constants.pendingUpdateInfoKey) as? Data,
               let cached = try? JSONDecoder().decode(UpdateController.PendingUpdateInfo.self, from: data) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM dd yyyy"
                let releaseTitle = formatter.string(from: cached.date)

                let cachedVersion = "\(cached.version) (\(cached.build))"
                let status = currentVersion == cachedVersion ? ReleaseNotesValues.Status.loaded : ReleaseNotesValues.Status.updateReady

                self.init(status: status,
                          currentVersion: currentVersion,
                          latestVersion: cachedVersion,
                          lastUpdate: lastUpdate,
                          releaseTitle: releaseTitle,
                          releaseNotes: cached.releaseNotes,
                          releaseNotesPrivacyPro: cached.releaseNotesPrivacyPro,
                          downloadProgress: 0.00,
                          automaticUpdate: updateController.areAutomaticUpdatesEnabled)
                return
            }

            pixelKit?.fire(GeneralPixel.releaseNotesEmpty, frequency: .dailyAndCount)

            self.init(status: updateController.updateProgress.toStatus,
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

        // Hack: this is a bit of a hack to get the action button in our Release Notes to show
        // the appropriate action.  This code only executes if autor-restarts are NOT allowed
        // which means we're on the new update behavior.
        //
        // The rationale for this change is explained here:
        // https://app.asana.com/1/137249556945/task/1210262960023979/comment/1210277947927308?focus=true
        //
        // This was done to provide a quick solution to an issue found during a ship review.
        //
        let automaticUpdate = updateController.useLegacyAutoRestartLogic ? updateController.areAutomaticUpdatesEnabled : updateController.isAtRestartCheckpoint

        self.init(status: status,
                  currentVersion: currentVersion,
                  latestVersion: latestUpdate.versionString,
                  lastUpdate: lastUpdate,
                  releaseTitle: latestUpdate.title,
                  releaseNotes: latestUpdate.releaseNotes,
                  releaseNotesPrivacyPro: latestUpdate.releaseNotesPrivacyPro,
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

#else

protocol ReleaseNotesTabExtensionProtocol: AnyObject, NavigationResponder {}

extension ReleaseNotesTabExtension: ReleaseNotesTabExtensionProtocol, TabExtension {
    func getPublicProtocol() -> ReleaseNotesTabExtensionProtocol { self }
}

extension TabExtensions {
    var releaseNotes: ReleaseNotesTabExtensionProtocol? { resolve(ReleaseNotesTabExtension.self) }
}

final class ReleaseNotesTabExtension: NavigationResponder {
}

#endif
