//
//  DuckPlayer.swift
//  DuckDuckGo
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
import Common
import Combine
import Foundation
import WebKit
import UserScript
import Core
import ContentScopeScripts
import SwiftUI

/// Values that the frontend can use to determine the current state.
struct InitialPlayerSettings: Codable {
    struct PlayerSettings: Codable {
        let pip: PIP
        let customError: CustomError
    }

    struct PIP: Codable {
        let status: Status
    }

    struct Platform: Codable {
        let name: String
    }

    struct CustomError: Codable {
        let state: Status
        let signInRequiredSelector: String
    }

    enum Status: String, Codable {
        case enabled
        case disabled
    }

    enum Environment: String, Codable {
        case development
        case production
    }

    let userValues: UserValues
    let ui: UIValues
    let settings: PlayerSettings
    let platform: Platform
    let locale: String
    let localeStrings: String?
}

/// Values that the frontend can use to determine user settings.
public struct UserValues: Codable {
    enum CodingKeys: String, CodingKey {
        case duckPlayerMode = "privatePlayerMode"
        case askModeOverlayHidden = "overlayInteracted"
    }
    let duckPlayerMode: DuckPlayerMode
    let askModeOverlayHidden: Bool
}

/// UI-related values for the frontend.
public struct UIValues: Codable {
    enum CodingKeys: String, CodingKey {
        case allowFirstVideo
    }
    let allowFirstVideo: Bool
}

// Wrapper to allow sibling properties on each event in the future.
struct TelemetryEvent: Decodable {
    let attributes: Attributes
}

// This is the first example of a new telemetry event
struct ImpressionAttributes: Decodable {
    enum Layout: String, Decodable {
        case landscape = "landscape-layout"
    }

    let name: String
    let value: Layout
}

// Designed to represent the discriminated union used by the FE (where all events are schema-driven)
enum Attributes: Decodable {

    // more events can be added here later, without needing a new handler
    case impression(ImpressionAttributes)

    private enum CodingKeys: String, CodingKey {
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)

        switch name {
        case "impression":
            let attributes = try ImpressionAttributes(from: decoder)
            self = .impression(attributes)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "Unknown name value: \(name)"
            )
        }
    }
}

/// Protocol defining the Duck Player functionality.
protocol DuckPlayerControlling: AnyObject {

    /// The current Duck Player settings.
    var settings: DuckPlayerSettings { get }

    /// The host view controller, if any.
    var hostView: DuckPlayerHosting? { get }

    // Navigation Request Publisher to notify when DuckPlayer needs direct Youtube Nav
    var youtubeNavigationRequest: PassthroughSubject<URL, Never> { get }

    /// Publisher that emits when Native DuckPlayer is dismissed
    var playerDismissedPublisher: PassthroughSubject<Void, Never> { get }

    /// Initializes a new instance of DuckPlayer with the provided settings and feature flagger.
    ///
    /// - Parameters:
    ///   - settings: The Duck Player settings.
    ///   - featureFlagger: The feature flag manager.
    ///   - nativeUIPresenter: The native UI presenter.
    ///   - featureDiscovery: Storage for saying this feature has been used.
    init(settings: DuckPlayerSettings,
         featureFlagger: FeatureFlagger,
         nativeUIPresenter: DuckPlayerNativeUIPresenting,
         featureDiscovery: FeatureDiscovery)

    /// Sets user values received from the web content.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    /// - Returns: An optional `Encodable` response.
    func setUserValues(params: Any, message: WKScriptMessage) -> Encodable?

    /// Retrieves user values to send to the web content.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    /// - Returns: An optional `Encodable` response.
    func getUserValues(params: Any, message: WKScriptMessage) -> Encodable?

    /// Opens a video in Duck Player within the specified web view.
    ///
    /// - Parameters:
    ///   - url: The URL of the video.
    ///   - webView: The web view to load the video in.
    @MainActor func openVideoInDuckPlayer(url: URL, webView: WKWebView)

    /// Opens DuckPlayer Settings
    func openDuckPlayerSettings()

    /// Opens Duck Player settings from a web view
    /// This is an alias for openDuckPlayerSettings()
    /// Parameters are ignored but added to match the signature of the generic Webview Handlers
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    func openDuckPlayerSettings(params: Any, message: WKScriptMessage) async -> Encodable?

    /// Opens Duck Player information modal.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    func openDuckPlayerInfo(params: Any, message: WKScriptMessage) async -> Encodable?

    /// Handles a YouTube Error event from the web view
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    func handleYoutubeError(params: Any, message: WKScriptMessage) async -> Encodable?

    /// Sends a telemetry event from the FE.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    func telemetryEvent(params: Any, message: WKScriptMessage) async -> Encodable?

    /// Performs initial setup for the player.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    /// - Returns: An optional `Encodable` response.
    func initialSetupPlayer(params: Any, message: WKScriptMessage) async -> Encodable?

    /// Performs initial setup for the overlay.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    /// - Returns: An optional `Encodable` response.
    func initialSetupOverlay(params: Any, message: WKScriptMessage) async -> Encodable?

    /// Sets the host view controller for presenting modals.
    ///
    /// - Parameter vc: The view controller to set as host.
    func setHostViewController(_ vc: DuckPlayerHosting)

    /// Loads a native DuckPlayerView
    ///
    /// - Parameters:
    ///   - videoID: The ID of the video to load
    ///   - source: The source of the video navigation.
    @MainActor func loadNativeDuckPlayerVideo(videoID: String, source: DuckPlayer.VideoNavigationSource, timestamp: TimeInterval?)

    /// Presents a bottom sheet asking the user how they want to open the video
    ///
    /// - Parameters:
    ///   - videoID: The YouTube video ID to be played
    ///   - timestamp: The current timestamp of the video
    @MainActor func presentPill(for videoID: String, timestamp: TimeInterval?)

    /// Dismisses the bottom sheet
    /// - Parameters:
    ///   - reset: Whether to reset the pill state
    ///   - animated: Whether to animate the dismissal
    ///   - programatic: Whether the dismissal was triggered programatically
    @MainActor func dismissPill(reset: Bool, animated: Bool, programatic: Bool)

    /// Hides the bottom sheet when browser chrome is hidden
    @MainActor func hidePillForHiddenChrome()

    /// Shows the bottom sheet when browser chrome is visible
    @MainActor func showPillForVisibleChrome()

    // Map Settings
    func mapLegacySettings()

    // Native UI - UserScript Methods    
    // These are used to notify the UserScript to trigger the appropriate actions
    // on the UserScript Broker    
    var muteAudioPublisher: PassthroughSubject<Bool, Never> { get }
    var mediaControlPublisher: PassthroughSubject<Bool, Never> { get }
    var currentTimeStampPublisher: PassthroughSubject<TimeInterval, Never> { get }
    var serpNotificationPublisher: PassthroughSubject<Bool, Never> { get }
    var urlChangedPublisher: PassthroughSubject<URL, Never> { get }
}

extension DuckPlayerControlling {

    // Convenience method to load a native DuckPlayerView - Default to other and nil timestamp
    func loadNativeDuckPlayerVideo(videoID: String) {
        Task { await loadNativeDuckPlayerVideo(videoID: videoID, source: DuckPlayer.VideoNavigationSource.other, timestamp: nil) }
    }
}

/// Implementation of the DuckPlayerControlling.
final class DuckPlayer: NSObject, DuckPlayerControlling {

    struct Constants {
        static let duckPlayerHost: String = "player"
        static let commonName = "Duck Player"
        static let translationFile = "duckplayer"
        static let translationFileExtension = "json"
        static let defaultLocale = "en"
        static let translationPath = "pages/duckplayer/locales/"
        static let featureNameKey = "featureName"
        static let landscapeUIAutohideDelay: CGFloat = 4.0
        static let chromeShowHideAnimationDuration: CGFloat = 0.4
    }

    private(set) var settings: DuckPlayerSettings
    private(set) weak var hostView: DuckPlayerHosting?

    private var featureFlagger: FeatureFlagger
    private var hideBrowserChromeTimer: Timer?
    private var tapGestureRecognizer: UITapGestureRecognizer?

    // Native Player
    private var nativePlayerCancellables = Set<AnyCancellable>()

    private lazy var localeStrings: String? = {
        let languageCode = Locale.current.languageCode ?? Constants.defaultLocale
        if let localizedFile = ContentScopeScripts.Bundle.path(forResource: Constants.translationFile,
                                                               ofType: Constants.translationFileExtension,
                                                               inDirectory: "\(Constants.translationPath)\(languageCode)") {
            return try? String(contentsOfFile: localizedFile)
        }
        return nil
    }()

    private struct WKMessageData: Codable {
        var context: String?
        var featureName: String?
        var method: String?
    }

    private enum FeatureName: String {
        case page = "duckPlayerPage"
        case overlay = "duckPlayer"
    }

    enum VideoNavigationSource: String {
        case youtube
        case serp
        case other
    }

    // A published subject to notify when a Youtube navigation request is needed
    var youtubeNavigationRequest: PassthroughSubject<URL, Never>

    /// Publisher to notify when DuckPlayer is dismissed
    var playerDismissedPublisher: PassthroughSubject<Void, Never>

    /// Native UI Presenter
    let nativeUIPresenter: DuckPlayerNativeUIPresenting
    private var nativeUIPresenterCancellables = Set<AnyCancellable>()
    
    /// Publishers to communicate between Native UI -> UserScript
    // DuckPlayer acts as a two way bridge between the UserScripts and the Native UI
    var muteAudioPublisher: PassthroughSubject<Bool, Never>
    var mediaControlPublisher: PassthroughSubject<Bool, Never>
    var currentTimeStampPublisher: PassthroughSubject<TimeInterval, Never>
    var serpNotificationPublisher: PassthroughSubject<Bool, Never>
    var urlChangedPublisher: PassthroughSubject<URL, Never>

    /// Used for recording discovery of a feature
    let featureDiscovery: FeatureDiscovery
    
    /// Current timestamp from YouTube.com for entry pill handling
    private var youtubeTimestamp: TimeInterval?
    
    /// Current timestamp from DuckPlayer view for re-entry pill handling
    private var duckPlayerTimestamp: TimeInterval?
    
    /// Current video ID being tracked
    private var currentVideoID: String?
    
    /// Whether the current video has been shown in DuckPlayer before
    private var hasBeenShown: Bool = false

    /// Initializes a new instance of DuckPlayer with the provided settings and feature flagger.
    ///
    /// - Parameters:
    ///   - settings: The Duck Player settings.
    ///   - featureFlagger: The feature flag manager.
    ///   - nativeUIPresenter: The native UI presenter.
    init(settings: DuckPlayerSettings = DuckPlayerSettingsDefault(),
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         nativeUIPresenter: DuckPlayerNativeUIPresenting,
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery()) {
        self.settings = settings
        self.featureFlagger = featureFlagger
        self.youtubeNavigationRequest = PassthroughSubject<URL, Never>()
        self.playerDismissedPublisher = PassthroughSubject<Void, Never>()
        self.nativeUIPresenter = nativeUIPresenter
        self.muteAudioPublisher = PassthroughSubject<Bool, Never>()
        self.mediaControlPublisher = PassthroughSubject<Bool, Never>()
        self.currentTimeStampPublisher = PassthroughSubject<TimeInterval, Never>()
        self.serpNotificationPublisher = PassthroughSubject<Bool, Never>()
        self.urlChangedPublisher = PassthroughSubject<URL, Never>()
        self.featureDiscovery = featureDiscovery
        super.init()
        setupSubscriptions()

        NotificationCenter.default.addObserver(self,
                                             selector: #selector(handleChromeVisibilityChange(_:)),
                                             name: .browserChromeVisibilityChanged,
                                             object: nil)

        // Map legacy settings
        mapLegacySettings()
    }

    // Add a convenience initializer that creates a new presenter
    convenience init(settings: DuckPlayerSettings = DuckPlayerSettingsDefault(),
                     featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.init(settings: settings,
                  featureFlagger: featureFlagger,
                  nativeUIPresenter: DuckPlayerNativeUIPresenter())
    }

    deinit {
        // Remove tap gesture recognizer
        if let tapGestureRecognizer = tapGestureRecognizer {
            hostView?.view.removeGestureRecognizer(tapGestureRecognizer)
        }

        // Remove notification observers
        NotificationCenter.default.removeObserver(self)

        // Cancel timer
        hideBrowserChromeTimer?.invalidate()
        hideBrowserChromeTimer = nil

        // Clear cancellables
        nativePlayerCancellables.removeAll()
        nativeUIPresenterCancellables.removeAll()

        hostView = nil
    }

    /// Sets the host view controller for presenting modals.
    ///
    /// - Parameter vc: The view controller to set as host.
    public func setHostViewController(_ vc: DuckPlayerHosting) {
        hostView = vc
    }

    private func addTapGestureRecognizer() {
        guard let hostView = hostView,
              tapGestureRecognizer == nil,
              let url = hostView.url,
              url.isDuckPlayer else {
            return
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        hostView.view.addGestureRecognizer(tapGesture)
        tapGestureRecognizer = tapGesture
    }

    private func removeTapGestureRecognizer() {
        if let tapGestureRecognizer = tapGestureRecognizer {
            hostView?.view.removeGestureRecognizer(tapGestureRecognizer)
            self.tapGestureRecognizer = nil
        }
    }

    /// Handles tap gestures in the hostViewController
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if let url = hostView?.url, url.isDuckPlayer {
            let orientation = UIDevice.current.orientation
            if orientation.isLandscape {
                hostView?.showChrome()
                Task { await showPillForVisibleChrome() }
            }
        }
    }

    /// Sets up a hide timer for the navigation and toolbars when the user is in landscape mode
    private func setupHideBrowserChromeTimer() {
        hideBrowserChromeTimer?.invalidate()

        weak var weakHostView = hostView
        hideBrowserChromeTimer = Timer.scheduledTimer(withTimeInterval: Constants.landscapeUIAutohideDelay, repeats: false) { _ in
            DispatchQueue.main.async {
                let orientation = UIDevice.current.orientation
                if orientation.isLandscape {
                    weakHostView?.hideChrome()
                }
            }
        }
    }

    /// Loads a native DuckPlayerView and sets flag that DuckPlayer has been used.
    func loadNativeDuckPlayerVideo(videoID: String, source: VideoNavigationSource = .other, timestamp: TimeInterval? = nil) {

        // Mark that Native UI was used
        settings.nativeUIWasUsed = true
        
        guard let hostView = hostView else { return }
        featureDiscovery.setWasUsedBefore(.duckPlayer)

        Task { @MainActor in
            let publishers = nativeUIPresenter.presentDuckPlayer(videoID: videoID, source: source, in: hostView, title: nil, timestamp: timestamp)

            publishers.navigation
                .sink { [weak self] url in
                    self?.youtubeNavigationRequest.send(url)
                }
                .store(in: &nativeUIPresenterCancellables)

            publishers.settings
                .sink { [weak self] in
                    self?.openDuckPlayerSettings()
                }
                .store(in: &nativeUIPresenterCancellables)
        }
    }

    // MARK: - Common Message Handlers

    /// Sets user values received from the web content.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    /// - Returns: An optional `Encodable` response.
    public func setUserValues(params: Any, message: WKScriptMessage) -> Encodable? {
        guard let userValues: UserValues = DecodableHelper.decode(from: params) else {
            assertionFailure("DuckPlayer: expected JSON representation of UserValues")
            return nil
        }

        Task {
            // Fire pixels for analytics
            await firePixels(message: message, userValues: userValues)

            // Update settings based on user values
            await updateSettings(userValues: userValues)
        }
        return userValues
    }

    /// Updates Duck Player settings based on user values.
    ///
    /// - Parameter userValues: The user values to update settings with.
    private func updateSettings(userValues: UserValues) async {
        settings.mode = userValues.duckPlayerMode
        settings.askModeOverlayHidden = userValues.askModeOverlayHidden
    }

    /// Registers an Nootification observer for orientation changes
    private func registerOrientationSubscriber() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(orientationDidChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }

    /// Called when the Orientation notification is changed
    @objc private func orientationDidChange() {
        let orientation = UIDevice.current.orientation

        // Only proceed with orientation change if DuckPlayer is visible
        guard hostView?.isTabCurrentlyPresented() ?? false,
              let url = hostView?.url,
              url.isDuckPlayer else {
            return
        }
        handleOrientationChange(orientation)
    }

    /// Handles UI Updates based on orientation.  When switching to landscape, we hide
    /// Navigation and Tabbar to enable "Fake" full screen mode.
    private func handleOrientationChange(_ orientation: UIDeviceOrientation) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        switch orientation {
        case .portrait, .portraitUpsideDown:
            handlePortraitOrientation()
            removeTapGestureRecognizer()
        case .landscapeLeft, .landscapeRight:
            handleLandscapeOrientation()
            addTapGestureRecognizer()
        case .unknown, .faceUp, .faceDown:
            handleDefaultOrientation()
            removeTapGestureRecognizer()
        @unknown default:
            return
        }
    }

    /// Handle Portrait rotation
    private func handlePortraitOrientation() {
        hostView?.showChrome()
        hideBrowserChromeTimer?.invalidate()
        hideBrowserChromeTimer = nil
        hostView?.setupWebViewForPortraitVideo()
    }

    /// Handle Landscape rotation
    private func handleLandscapeOrientation() {
        hostView?.setupWebViewForLandscapeVideo()
        hostView?.hideChrome()
    }

    /// Default rotation should be portrait mode
    private func handleDefaultOrientation() {
        hostView?.setupWebViewForPortraitVideo()
    }

    /// Retrieves user values to send to the web content.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    /// - Returns: An optional `Encodable` response.
    public func getUserValues(params: Any, message: WKScriptMessage) -> Encodable? {
        if featureFlagger.isFeatureOn(.duckPlayer) {
            return encodeUserValues()
        }
        return nil
    }

    /// Opens a video in Duck Player within the specified web view.
    ///
    /// - Parameters:
    ///   - url: The URL of the video.
    ///   - webView: The web view to load the video in.
    @MainActor
    public func openVideoInDuckPlayer(url: URL, webView: WKWebView) {
        featureDiscovery.setWasUsedBefore(.duckPlayer)
        webView.load(URLRequest(url: url))
    }

    /// Performs initial setup for the player and sets flag that DuckPlayer has been used.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    /// - Returns: An optional `Encodable` response.
    @MainActor
    public func initialSetupPlayer(params: Any, message: WKScriptMessage) async -> Encodable? {
        let webView = message.webView
        return await self.encodedPlayerSettings(with: webView)
    }

    /// Performs initial setup for the overlay and sets flag that DuckPlayer has been used.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    /// - Returns: An optional `Encodable` response.
    @MainActor
    public func initialSetupOverlay(params: Any, message: WKScriptMessage) async -> Encodable? {
        let webView = message.webView
        return await self.encodedPlayerSettings(with: webView)
    }

    /// Opens Duck Player Settings Page
    public func openDuckPlayerSettings() {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.duckPlayer,
            userInfo: nil
        )
    }

    /// Opens Duck Player settings from a web view    
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    public func openDuckPlayerSettings(params: Any, message: WKScriptMessage) async -> Encodable? {
        openDuckPlayerSettings()
        return nil
    }

    /// Sends a telemetry event from the FE.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    @MainActor
    public func telemetryEvent(params: Any, message: WKScriptMessage) async -> Encodable? {
        // Not currently accepting any telemetry events
        return nil
    }

    /// Handles a YouTube Error event from the web view
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    @MainActor
    public func handleYoutubeError(params: Any, message: WKScriptMessage) async -> Encodable? {
        let (volumePixel, dailyPixel) = getPixelsForYouTubeErrorParams(params)
        DailyPixel.fire(pixel: dailyPixel)
        Pixel.fire(pixel: volumePixel)
        return nil
    }

    /// Opens Duck Player information modal.
    ///
    /// - Parameters:
    ///   - params: Parameters from the web content.
    ///   - message: The script message containing the parameters.
    @MainActor
    public func openDuckPlayerInfo(params: Any, message: WKScriptMessage) async -> Encodable? {
        guard let body = message.body as? [String: Any],
              let featureNameString = body[Constants.featureNameKey] as? String,
              let featureName = FeatureName(rawValue: featureNameString) else {
            return nil
        }
        let context: DuckPlayerModalPresenter.PresentationContext = featureName == .page ? .youtube : .SERP
        presentDuckPlayerInfo(context: context)
        return nil
    }

    /// Presents the Duck Player info modal.
    ///
    /// - Parameter context: The presentation context for the modal.
    @MainActor
    public func presentDuckPlayerInfo(context: DuckPlayerModalPresenter.PresentationContext) {

        // Need to cast to TabVC for now - Will be remove once DuckPlayer NativeUI is released
        guard let view = hostView as? TabViewController else { return }
        DuckPlayerModalPresenter(context: context).presentDuckPlayerFeatureModal(on: view)
    }

    /// Encodes user values for sending to the web content.
    ///
    /// - Returns: An instance of `UserValues`.
    private func encodeUserValues() -> UserValues {
        return UserValues(
            duckPlayerMode: featureFlagger.isFeatureOn(.duckPlayer) ? settings.mode : .disabled,
            askModeOverlayHidden: settings.askModeOverlayHidden
        )
    }

    /// Encodes UI values for sending to the web content.
    ///
    /// - Returns: An instance of `UIValues`.
    private func encodeUIValues() -> UIValues {
        UIValues(
            allowFirstVideo: settings.allowFirstVideo
        )
    }

    /// Prepares and encodes player settings to send to the web content.
    ///
    /// - Parameter webView: The web view to check for PiP capability.
    /// - Returns: An instance of `InitialPlayerSettings`.
    @MainActor
    private func encodedPlayerSettings(with webView: WKWebView?) async -> InitialPlayerSettings {
        let isPiPEnabled = webView?.configuration.allowsPictureInPictureMediaPlayback == true
        let pip = InitialPlayerSettings.PIP(status: isPiPEnabled ? .enabled : .disabled)
        let customError = InitialPlayerSettings.CustomError(state: settings.customError ? .enabled : .disabled, signInRequiredSelector: settings.customErrorSettings?.signInRequiredSelector ?? "")
        let platform = InitialPlayerSettings.Platform(name: "ios")
        let locale = Locale.current.languageCode ?? "en"
        let playerSettings = InitialPlayerSettings.PlayerSettings(pip: pip, customError: customError)

        let userValues = encodeUserValues()
        let uiValues = encodeUIValues()
        let settings = InitialPlayerSettings(
            userValues: userValues,
            ui: uiValues,
            settings: playerSettings,
            platform: platform,
            locale: locale,
            localeStrings: localeStrings
        )
        return settings
    }

    /// Fires analytics pixels based on user interactions.
    ///
    /// - Parameters:
    ///   - message: The script message containing the interaction data.
    ///   - userValues: The user values to determine which pixels to fire.
    @MainActor
    private func firePixels(message: WKScriptMessage, userValues: UserValues) {

        // Get the webView URL
        guard let webView = message.webView, let url = webView.url else {
            return
        }

        // Based on the URL, determine which pixels to fire
        let isSERP = url.isDuckDuckGoSearch

        // Assume we are in the SERP Overlay
        if isSERP {
            switch userValues.duckPlayerMode {
            case .enabled:
                Pixel.fire(pixel: .duckPlayerSettingsAlwaysOverlaySERP)
            case .disabled:
                Pixel.fire(pixel: .duckPlayerSettingsNeverOverlaySERP)
            default: break
            }

            // Assume we are in the Youtube Overlay
        } else {
            switch userValues.duckPlayerMode {
            case .enabled:
                Pixel.fire(pixel: .duckPlayerSettingsAlwaysOverlayYoutube)
            case .disabled:
                Pixel.fire(pixel: .duckPlayerSettingsNeverOverlayYoutube)
            default: break
            }
        }

    }

    /// Hides the bottom sheet when browser chrome is hidden
    @MainActor
    func hidePillForHiddenChrome() {
        nativeUIPresenter.hideBottomSheetForHiddenChrome()
    }

    /// Shows the bottom sheet when browser chrome is visible
    @MainActor
    func showPillForVisibleChrome() {
        nativeUIPresenter.showBottomSheetForVisibleChrome()
    }

    /// Presents a bottom sheet asking the user how they want to open the video and sets flag that DuckPlayer has been used.
    ///
    /// - Parameters:
    ///   - videoID: The YouTube video ID to be played
    ///   - timestamp: The timestamp of the video
    func presentPill(for videoID: String, timestamp: TimeInterval?) {
        guard let hostView = hostView else { return }

        Task { @MainActor in
            if hostView.url?.isYoutubeWatch ?? false {
                // Determine which timestamp to use based on pill type logic
                let appropriateTimestamp = self.getAppropriateTimestamp(for: videoID)
                nativeUIPresenter.presentPill(for: videoID, in: hostView, timestamp: appropriateTimestamp)
            }
        }
    }

    /// Dismisses the bottom sheet
    /// - Parameters:
    ///   - reset: Whether to reset the pill state
    ///   - animated: Whether to animate the dismissal
    ///   - programatic: Whether the dismissal was triggered programatically
    @MainActor
    func dismissPill(reset: Bool, animated: Bool, programatic: Bool) {
        nativeUIPresenter.dismissPill(reset: reset, animated: animated, programatic: programatic)
    }

    @objc private func handleChromeVisibilityChange(_ notification: Notification) {
        if let url = hostView?.webView.url,
            url.isYoutubeWatch,
            let isHidden = notification.userInfo?["isHidden"] as? Bool {

            if isHidden {
                Task { await hidePillForHiddenChrome() }
            } else {
                Task { await showPillForVisibleChrome() }
            }
        }
    }

    private func setupSubscriptions() {
        // Subscribe to timestamp updates from the UserScript (YouTube.com)
        currentTimeStampPublisher
            .sink { [weak self] timestamp in
                self?.youtubeTimestamp = timestamp
            }
            .store(in: &nativeUIPresenterCancellables)
        
        // Set up the subscription once and keep it alive
        nativeUIPresenter.videoPlaybackRequest
            .sink { [weak self] videoDetails in
                let (videoID, pillTimestamp, pillType) = videoDetails
                
                // When on youtube, we use the timestamp from the pill if it's an entry pill
                // Otherwise, we use the timestamp from the UserScript (DuckPlayer)
                Task {
                    let timestamp = pillType == .entry ? self?.youtubeTimestamp : pillTimestamp
                    await self?.loadNativeDuckPlayerVideo(videoID: videoID, source: .youtube, timestamp: timestamp)
                }
            }
            .store(in: &nativeUIPresenterCancellables)

        nativeUIPresenter.presentDuckPlayerRequest
            .sink { [weak self] in
                guard let self = self else { return }
                // Pause media playback when presenting the full player
                self.mediaControlPublisher.send(true)
            }
            .store(in: &nativeUIPresenterCancellables)
        
        nativeUIPresenter.duckPlayerTimestampUpdate
            .sink { [weak self] timestamp in
                self?.storeDuckPlayerTimestamp(timestamp)
            }
            .store(in: &nativeUIPresenterCancellables)

        registerOrientationSubscriber()
    }
    
    /// Determines the appropriate timestamp based on pill type logic
    /// - Parameter videoID: The video ID being presented
    /// - Returns: YouTube timestamp for entry pills, DuckPlayer timestamp for re-entry pills
    private func getAppropriateTimestamp(for videoID: String) -> TimeInterval? {
        // Update current video tracking
        if currentVideoID != videoID {
            currentVideoID = videoID
            hasBeenShown = false  // Reset for new video
        }
        
        let duckPlayerSettings = DuckPlayerSettingsDefault()
        
        // If priming modal hasn't been presented, it's a welcome pill (use YouTube timestamp)
        if !duckPlayerSettings.primingMessagePresented {
            return youtubeTimestamp
        }
        
        // Logic for returning users: entry vs re-entry
        if hasBeenShown {
            // Re-entry pill - use DuckPlayer timestamp
            return duckPlayerTimestamp
        } else {
            // Entry pill - use YouTube timestamp
            return youtubeTimestamp
        }
    }
    
    /// Stores timestamp from DuckPlayer view dismissal
    /// This should be called when DuckPlayer view is dismissed with a timestamp
    func storeDuckPlayerTimestamp(_ timestamp: TimeInterval?) {
        duckPlayerTimestamp = timestamp
    }

    /// Returns tuple of Pixels for firing when a YouTube Error occurs
    private func getPixelsForYouTubeErrorParams(_ params: Any) -> (Pixel.Event, Pixel.Event) {
        if let paramsDict = params as? [String: Any],
           let errorParam = paramsDict["error"] as? String {
                switch errorParam {
                case "sign-in-required":
                    return (.duckPlayerYouTubeSignInErrorImpression, .duckPlayerYouTubeSignInErrorDaily)
                case "age-restricted":
                    return (.duckPlayerYouTubeAgeRestrictedErrorImpression, .duckPlayerYouTubeAgeRestrictedErrorDaily)
                case "no-embed":
                    return (.duckPlayerYouTubeNoEmbedErrorImpression, .duckPlayerYouTubeNoEmbedErrorDaily)
                default:
                    return (.duckPlayerYouTubeUnknownErrorImpression, .duckPlayerYouTubeUnknownErrorDaily)
                }
        }
        return (.duckPlayerYouTubeUnknownErrorImpression, .duckPlayerYouTubeUnknownErrorDaily)
    }

    /// Maps legacy settings to new settings
    // Maps DuckPlayerMode to NativeUIYoutubeMode
    // https://app.asana.com/1/137249556945/project/1204099484721401/task/1210320494056772?focus=true
    func mapLegacySettings() {
        if settings.nativeUI && !settings.nativeUISettingsMapped {
            switch settings.mode {
            case .enabled:
                settings.nativeUIYoutubeMode = .auto
                settings.nativeUISERPEnabled = true
            case .alwaysAsk:
                settings.nativeUIYoutubeMode = .ask
                settings.nativeUISERPEnabled = true
            case .disabled:
                settings.nativeUIYoutubeMode = .never
                settings.nativeUISERPEnabled = false
            }
            settings.nativeUISettingsMapped = true
        }
    }
}

extension DuckPlayer: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// Add UIAdaptivePresentationControllerDelegate to handle sheet dismissal
extension DuckPlayer: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        playerDismissedPublisher.send()
    }
}
