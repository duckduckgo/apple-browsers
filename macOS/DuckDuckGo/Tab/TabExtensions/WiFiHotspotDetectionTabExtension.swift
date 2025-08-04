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

import BrowserServicesKit
import Combine
import Common
import FeatureFlags
import Foundation
import Navigation
import os.log
import WebKit
import Cocoa

protocol CaptivePortalHandler {
    @MainActor func openCaptivePortal(url: URL)
    @MainActor func closeCaptivePortal(url: URL)
    @MainActor func subscribeToConnectivityRestoration(service: HotspotDetectionServiceProtocol)
}

@MainActor
final class CaptivePortalPopupManager: CaptivePortalHandler {
    private var activePopupWindows: [URL: NSWindow] = [:]
    private var cancellables = Set<AnyCancellable>()

    nonisolated init() {}

    func openCaptivePortal(url: URL) {
        // Check if popup already exists for this URL
        if let existingWindow = activePopupWindows[url] {
            // Activate existing window
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Create new Fire tab for the captive portal (disposable session)
        let tab = Tab(content: .url(url, source: .ui), shouldLoadInBackground: false, burnerMode: BurnerMode(isBurner: true))

        // Use WindowsManager to create proper Fire popup window with appropriate size
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.fallbackHeadlessScreenFrame
        let contentSize = NSSize(width: min(screenFrame.width, 1024), height: min(screenFrame.height, 768))

        // Create popup window and store reference
        // Force popup creation even in fullscreen mode for captive portal
        if let window = WindowsManager.openPopUpWindow(with: tab, origin: nil, contentSize: contentSize, forcePopup: true) {
            activePopupWindows[url] = window

            // Set up cleanup when window closes
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { () in
                    _=self?.activePopupWindows.removeValue(forKey: url)
                }
            }
        }
    }

    func closeCaptivePortal(url: URL) {
        if let window = activePopupWindows[url] {
            window.close()
            activePopupWindows.removeValue(forKey: url)
        }
    }

    func subscribeToConnectivityRestoration(service: HotspotDetectionServiceProtocol) {
        // Monitor service state to close popup when connectivity is restored
        service.statePublisher
            .filter { $0 == .connected }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.closeAllCaptivePortalPopups()
                // Cancel all subscriptions after connectivity is restored
                self?.cancellables.removeAll()
            }
            .store(in: &cancellables)
    }

    private func closeAllCaptivePortalPopups() {
        for (_, window) in activePopupWindows {
            window.close()
        }
        activePopupWindows.removeAll()
    }
}

struct DefaultCaptivePortalHandler: CaptivePortalHandler {
    private let popupManager: CaptivePortalPopupManager

    init(popupManager: CaptivePortalPopupManager) {
        self.popupManager = popupManager
    }

    func openCaptivePortal(url: URL) {
        popupManager.openCaptivePortal(url: url)
    }

    func closeCaptivePortal(url: URL) {
        popupManager.closeCaptivePortal(url: url)
    }

    func subscribeToConnectivityRestoration(service: HotspotDetectionServiceProtocol) {
        popupManager.subscribeToConnectivityRestoration(service: service)
    }
}

final class WiFiHotspotDetectionTabExtension {
    private weak var permissionModel: PermissionModel?
    private let hotspotDetectionService: HotspotDetectionServiceProtocol
    private let featureFlagger: FeatureFlagger
    private let captivePortalHandler: CaptivePortalHandler
    private(set) var cancellable: AnyCancellable?
    private weak var hotspotAuthQuery: PermissionAuthorizationQuery?
    private weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()
    private var hasDetectedHotspot = false

    init(permissionModel: PermissionModel?,
         hotspotDetectionService: HotspotDetectionServiceProtocol,
         featureFlagger: FeatureFlagger,
         captivePortalHandler: CaptivePortalHandler? = nil,
         webViewPublisher: some Publisher<WKWebView, Never>) {
        self.permissionModel = permissionModel
        self.hotspotDetectionService = hotspotDetectionService
        self.featureFlagger = featureFlagger
        self.captivePortalHandler = captivePortalHandler ?? DefaultCaptivePortalHandler(popupManager: CaptivePortalPopupManager())

        // Subscribe to webView changes
        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }.store(in: &cancellables)
    }
}

extension WiFiHotspotDetectionTabExtension: NavigationResponder {

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard featureFlagger.isFeatureOn(.hotspotDetection) else { return }
        guard navigation.isCurrent else { return }

        // Subscribe to hotspot detection service on navigation failure if not already subscribed
        if cancellable == nil {
            subscribeToHotspotService(originalURL: navigation.url)
        } else if hasDetectedHotspot {
            // hotspot already detected but auth query dismissed
            showWiFiHotspotPermission(originalURL: navigation.url)
        }
    }

    @MainActor
    func willStart(_ navigation: Navigation) {
        // Clear error and hotspot detection flag when new navigation starts
        if navigation.isCurrent {
            hasDetectedHotspot = false
        }
    }

    @MainActor
    func navigationDidFinish(_ navigation: Navigation) {
        // Clear error and hotspot detection flag on successful navigation
        if navigation.isCurrent, navigation.navigationAction.navigationType != .alternateHtmlLoad {
            hasDetectedHotspot = false
        }
    }

    private func subscribeToHotspotService(originalURL: URL) {
        cancellable = hotspotDetectionService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated {
                    self?.handleHotspotStateChange(state, originalURL: originalURL)
                }
            }
    }

    @MainActor
    private func handleHotspotStateChange(_ state: HotspotConnectivityState, originalURL: URL) {
        switch state {
        case .unknown:
            // Service stopped or initial state - no action needed
            break
        case .connected:
            // Connection restored - dismiss our hotspot auth query and unsubscribe from service
            hotspotAuthQuery?.handleDecision(grant: false, remember: false)
            hotspotAuthQuery = nil
            unsubscribeFromHotspotService()

            // Reload page if we previously detected a hotspot
            // This ensures all tabs that detected hotspot get reloaded, even if they didn't open the portal
            if hasDetectedHotspot,
               let webView {
                Logger.general.debug("WiFi connectivity restored after hotspot detection - reloading page")
                webView.reload()
            }

            // Reset hotspot detection flag
            hasDetectedHotspot = false
        case .hotspotAuth:
            // Hotspot authentication required - mark that we detected a hotspot
            hasDetectedHotspot = true
            // Show permission dialog
            showWiFiHotspotPermission(originalURL: originalURL)
            // Continue monitoring in case user authenticates
        }
    }

    private func unsubscribeFromHotspotService() {
        cancellable = nil
        Logger.general.debug("WiFiHotspotDetectionTabExtension unsubscribed from service")
    }

    @MainActor
    private func showWiFiHotspotPermission(originalURL: URL) {
        guard let permissionModel else { return }

        // Use the debug settings URL for the captive portal in DEBUG builds, otherwise use Firefox endpoint
        let captivePortalURL: URL = {
#if DEBUG && !APPSTORE
            return HotspotDetectionDebugSettings.shared.connectivityCheckURL
#else
            return URL(string: "http://detectportal.firefox.com/success.txt")!
#endif
        }()

        permissionModel.permissions([.wifiHotspot],
                                    requestedForDomain: captivePortalURL.host ?? "captive.portal",
                                    url: captivePortalURL) { [weak self] granted in
            if granted {
                // Open the captive portal page in a popup window
                Task { @MainActor in
                    self?.captivePortalHandler.openCaptivePortal(url: captivePortalURL)
                    // Subscribe to connectivity restoration for popup window management
                    if let hotspotService = self?.hotspotDetectionService {
                        self?.captivePortalHandler.subscribeToConnectivityRestoration(service: hotspotService)
                    }
                }
            }
        }

        // Store reference to the hotspot authorization query we just created
        hotspotAuthQuery = permissionModel.authorizationQuery
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
