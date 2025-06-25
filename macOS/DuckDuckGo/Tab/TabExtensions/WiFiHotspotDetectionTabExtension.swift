//
//  WiFiHotspotDetectionTabExtension.swift
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

import Combine
import Common
import Foundation
import Navigation
import os.log
import WebKit

final class WiFiHotspotDetectionTabExtension {
    private weak var permissionModel: PermissionModel?
    private let setContent: (Tab.TabContent) -> Void
    private var cancellables = Set<AnyCancellable>()
    private var isCheckingHotspot = false

    init(permissionModel: PermissionModel?, setContent: @escaping (Tab.TabContent) -> Void) {
        self.permissionModel = permissionModel
        self.setContent = setContent
    }
}

extension WiFiHotspotDetectionTabExtension: NavigationResponder {

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard navigation.isCurrent, !isCheckingHotspot else { return }

        // Only check for hotspot on specific network errors
//        switch error.code {
//        case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .timedOut:
            checkForWiFiHotspot(originalURL: navigation.url)
//        default:
//            break
//        }
    }

    private func checkForWiFiHotspot(originalURL: URL) {
        isCheckingHotspot = true

        Task {
            defer { isCheckingHotspot = false }

            // Test Firefox's success.txt URL for captive portal detection
            let testURL = URL(string: "http://detectportal.firefox.com/success.txt")!

            do {
                let (data, response) = try await URLSession.shared.data(from: testURL)

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {

                    let responseText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

                    // If we can reach the test URL but it doesn't return "success", it's likely a captive portal
                    if responseText != "success" {
                        await MainActor.run {
                            showWiFiHotspotPermission(redirectURL: response.url ?? testURL, originalURL: originalURL)
                        }
                    }
                }
            } catch {
                // Network error - likely not a captive portal issue
                Logger.general.debug("WiFi hotspot detection test failed: \(error)")
            }
        }
    }

    @MainActor
    private func showWiFiHotspotPermission(redirectURL: URL, originalURL: URL) {
        guard let permissionModel else { return }

        permissionModel.permissions([.wifiHotspot], requestedForDomain: redirectURL.host ?? "captive.portal", url: redirectURL) { [weak self] granted in
            if granted {
                // Open the captive portal page in a new tab
                if let tabCollectionViewModel = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel {
                    let tab = Tab(content: .url(redirectURL, source: .ui), shouldLoadInBackground: true, burnerMode: tabCollectionViewModel.burnerMode)
                    tabCollectionViewModel.insertOrAppend(tab: tab, selected: true)
                }
            }
        }
    }
}

protocol WiFiHotspotDetectionTabExtensionProtocol: AnyObject, NavigationResponder {
}

extension WiFiHotspotDetectionTabExtension: WiFiHotspotDetectionTabExtensionProtocol, TabExtension {
    func getPublicProtocol() -> WiFiHotspotDetectionTabExtensionProtocol { self }
}

extension TabExtensions {
    var wifiHotspotDetection: WiFiHotspotDetectionTabExtensionProtocol? {
        resolve(WiFiHotspotDetectionTabExtension.self)
    }
}
