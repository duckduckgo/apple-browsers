//
//  DuckPlayerNativeUIPresenter.swift
//  DuckDuckGo
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
import Foundation
import SwiftUI
import UIKit
import WebKit

/// Represents different types of constraint updates for DuckPlayer UI
public enum DuckPlayerConstraintUpdate {
    case showPill(height: CGFloat)
    case reset
}

protocol DuckPlayerNativeUIPresenting {

    var videoPlaybackRequest: PassthroughSubject<(videoID: String, timestamp: TimeInterval?, pillType: DuckPlayerNativeUIPresenter.PillType), Never> { get }
    var presentDuckPlayerRequest: PassthroughSubject<Void, Never> { get }
    var duckPlayerTimestampUpdate: PassthroughSubject<TimeInterval?, Never> { get }
    var pixelHandler: DuckPlayerPixelFiring.Type { get }

    @MainActor func presentPill(for videoID: String, in hostViewController: DuckPlayerHosting, timestamp: TimeInterval?)
    @MainActor func dismissPill(reset: Bool, animated: Bool, programatic: Bool)
    @MainActor func presentDuckPlayer(
        videoID: String, source: DuckPlayer.VideoNavigationSource, in hostViewController: DuckPlayerHosting, title: String?, timestamp: TimeInterval?
    ) -> (navigation: PassthroughSubject<URL, Never>, settings: PassthroughSubject<Void, Never>)
    @MainActor func showBottomSheetForVisibleChrome()
    @MainActor func hideBottomSheetForHiddenChrome()
}

/// A presenter class responsible for managing the native UI components of DuckPlayer.
/// This includes presenting entry pills and handling their lifecycle.
final class DuckPlayerNativeUIPresenter {
    public struct Notifications {
        public static let duckPlayerPillUpdated = Notification.Name("com.duckduckgo.duckplayer.pillUpdated")
    }

    // Keys used for the notification's userInfo dictionary
    public struct NotificationKeys {
        public static let isVisible = "isVisible"
    }

    /// The types of the pill available
    enum PillType {
        case entry
        case reEntry
        case welcome
    }

    struct Constants {
        // Used to update the WebView's bottom constraint
        // When pill is visible
        static let webViewRequiredBottomConstraint: CGFloat = 90
        static let primingModalHeight: CGFloat = 460
        static let detentIdentifier: String = "priming"

        // A presentation event is defined as a single instance of the priming modal being shown or duck
        // This define the logic for how many times the modal can be shown
        static let primingModalEventCountThreshold: Int = 1

        static let bottomPadding: CGFloat = 100
        static let height: CGFloat = 50
        static let fadeAnimationDuration: TimeInterval = 0.2
        static let visibleDuration: TimeInterval = 3.0
    }

    /// The container view model for the entry pill
    private(set) var containerViewModel: DuckPlayerContainer.ViewModel?

    /// The hosting controller for the container
    private(set) var containerViewController: UIHostingController<DuckPlayerContainer.Container<AnyView>>?

    /// References to the host view and source
    private(set) weak var hostView: DuckPlayerHosting?
    private(set) var source: DuckPlayer.VideoNavigationSource?
    internal var state: DuckPlayerState

    /// The view model for the player
    private(set) var playerViewModel: DuckPlayerViewModel?

    /// A publisher to notify when a video playback request is needed
    let videoPlaybackRequest = PassthroughSubject<(videoID: String, timestamp: TimeInterval?, pillType: PillType), Never>()
    
    /// A publisher to notify when the DuckPlayer should be presented - after tapping the pill
    let presentDuckPlayerRequest = PassthroughSubject<Void, Never>()
    
    /// A publisher to notify when a DuckPlayer timestamp should be stored
    let duckPlayerTimestampUpdate = PassthroughSubject<TimeInterval?, Never>()
    
    private var playerCancellables = Set<AnyCancellable>()
    @MainActor
    private var containerCancellables = Set<AnyCancellable>()

    // Other cancellables
    private var cancellables = Set<AnyCancellable>()

    /// Application Settings
    private var appSettings: AppSettings

    /// DuckPlayer Settings
    private var duckPlayerSettings: DuckPlayerSettings

    /// Current height of the OmniBar
    private var omniBarHeight: CGFloat = 0

    /// Bottom constraint for the container view
    private(set) var bottomConstraint: NSLayoutConstraint?

    /// Height of the current pill view
    private(set) var pillHeight: CGFloat = 0

    /// Notification center for posting notifications
    private let notificationCenter: NotificationCenter

    /// Determines if the priming modal should be shown
    private var shouldShowPrimingModal: Bool {
        !duckPlayerSettings.primingMessagePresented
    }

    /// Publisher for constraint updates
    private let constraintUpdatePublisher = PassthroughSubject<DuckPlayerConstraintUpdate, Never>()

    /// Public access to the constraint update publisher
    var constraintUpdates: AnyPublisher<DuckPlayerConstraintUpdate, Never> {
        constraintUpdatePublisher.eraseToAnyPublisher()
    }

    // State management for pill presentation
    private var presentedPillType: PillType?

    // Pixel Handler
    let pixelHandler: DuckPlayerPixelFiring.Type

    // MARK: - Public Methods
    ///
    /// - Parameter appSettings: The application settings
    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         duckPlayerSettings: DuckPlayerSettings = DuckPlayerSettingsDefault(),
         state: DuckPlayerState = DuckPlayerState(),
         notificationCenter: NotificationCenter = .default,
         pixelHandler: DuckPlayerPixelFiring.Type = DuckPlayerPixelHandler.self) {
        self.appSettings = appSettings
        self.duckPlayerSettings = duckPlayerSettings
        self.state = state
        self.notificationCenter = notificationCenter
        self.pixelHandler = pixelHandler
        setupNotificationObservers(notificationCenter: notificationCenter)
    }

    // To be replaced with AppUserDefaults.Notifications.addressBarPositionChanged after release
    // https://app.asana.com/1/137249556945/project/1207252092703676/task/1210323588862346?focus=true
    private func setupNotificationObservers(notificationCenter: NotificationCenter) {
        notificationCenter.addObserver(
            self,
            selector: #selector(handleOmnibarDidLayout),
            name: DefaultOmniBarView.didLayoutNotification,
            object: nil
        )

        // Add observers for app settings changes
        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppSettingsChange),
            name: AppUserDefaults.Notifications.duckPlayerSettingsUpdated,
            object: nil
        )

        // Subscribe to DuckPlayerSettings publisher        
        duckPlayerSettings.duckPlayerSettingsPublisher
            .sink { [weak self] _ in
                // Update local duckPlayerSettings with latest values
                self?.duckPlayerSettings = DuckPlayerSettingsDefault()
            }
            .store(in: &cancellables)
    }

    /// Updates the UI based on Ombibar Notification
    @objc func handleOmnibarDidLayout(_ notification: Notification) {
        guard let height = notification.object as? CGFloat else { return }
        omniBarHeight = height
        guard let bottomConstraint = bottomConstraint else { return }
        // To be replaced with AppUserDefaults.Notifications.addressBarPositionChanged after release
        // https://app.asana.com/1/137249556945/project/1207252092703676/task/1210323588862346?focus=true
        bottomConstraint.constant = appSettings.currentAddressBarPosition == .bottom ? -height : 0
    }

        /// Updates the UI based on Ombibar Notification
    @objc func handleAppSettingsChange(_ notification: Notification) {
        appSettings = AppDependencyProvider.shared.appSettings
    }

    /// Creates a container with the appropriate pill view based on the pill type
    @MainActor
    private func createContainerWithPill(
        for pillType: PillType,
        videoID: String,
        timestamp: TimeInterval?,
        containerViewModel: DuckPlayerContainer.ViewModel
    ) -> DuckPlayerContainer.Container<AnyView> {

        // Set pill height based on type
        pillHeight = Constants.webViewRequiredBottomConstraint

        if pillType == .welcome {
            // Create the welcome pill view model
            let welcomePillViewModel = DuckPlayerWelcomePillViewModel { [weak self] in
                self?.videoPlaybackRequest.send((videoID, timestamp, .welcome))
            }

            // Create the container view with the welcome pill
            return DuckPlayerContainer.Container(
                viewModel: containerViewModel,
                hasBackground: false,
                onDismiss: { [weak self] programatic in
                    self?.dismissPill(programatic: programatic)
                },
                onPresentDuckPlayer: { [weak self] in
                    guard let self = self else { return }
                    _ = self.presentDuckPlayer(
                        videoID: videoID,
                        source: .youtube,
                        in: self.hostView!,
                        title: nil,
                        timestamp: timestamp
                    )
                }
            ) { _ in
                AnyView(DuckPlayerWelcomePillView(viewModel: welcomePillViewModel))
            }
        } else if pillType == .entry {
            // Create the pill view model for entry type
            let pillViewModel = DuckPlayerEntryPillViewModel { [weak self] in
                self?.videoPlaybackRequest.send((videoID, timestamp, .entry))
            }

            // Create the container view with the pill view
            return DuckPlayerContainer.Container(
                viewModel: containerViewModel,
                hasBackground: false,
                onDismiss: { [weak self] programatic in
                    self?.dismissPill(programatic: programatic)
                },
                onPresentDuckPlayer: { [weak self] in
                    guard let self = self else { return }
                    _ = self.presentDuckPlayer(
                        videoID: videoID,
                        source: .youtube,
                        in: self.hostView!,
                        title: nil,
                        timestamp: timestamp
                    )
                }
            ) { _ in
                AnyView(DuckPlayerEntryPillView(viewModel: pillViewModel))
            }
        } else {
            // Create the mini pill view model for re-entry type
            let miniPillViewModel = DuckPlayerMiniPillViewModel(
                onOpen: { [weak self] in
                    self?.videoPlaybackRequest.send((videoID, timestamp, .reEntry))
                },
                videoID: videoID
            )

            // Create the container view with the mini pill view
            return DuckPlayerContainer.Container(
                viewModel: containerViewModel,
                hasBackground: false,
                onDismiss: { [weak self] programatic in
                    self?.dismissPill(programatic: programatic)
                },
                onPresentDuckPlayer: { [weak self] in
                    guard let self = self else { return }
                    _ = self.presentDuckPlayer(
                        videoID: videoID,
                        source: .youtube,
                        in: self.hostView!,
                        title: nil,
                        timestamp: timestamp
                    )
                }
            ) { _ in
                AnyView(DuckPlayerMiniPillView(viewModel: miniPillViewModel))
            }
        }
    }

    /// Updates the webView constraint based on the current pill height
    @MainActor
    private func updateWebViewConstraintForPillHeight() {
        constraintUpdatePublisher.send(.showPill(height: self.pillHeight))
    }

    /// Updates the content of an existing hosting controller with the appropriate pill view
    @MainActor
    private func updatePillContent(
        for pillType: PillType,
        videoID: String,
        timestamp: TimeInterval?,
        in hostingController: UIHostingController<DuckPlayerContainer.Container<AnyView>>
    ) {
        guard let containerViewModel = self.containerViewModel else { return }

        // Create a new container with the updated content
        let updatedContainer = createContainerWithPill(for: pillType, videoID: videoID, timestamp: timestamp, containerViewModel: containerViewModel)

        // Update the hosting controller's root view
        hostingController.rootView = updatedContainer
    }

    /// Resets the webView constraint to its default value
    @MainActor
    private func resetWebViewConstraint() {
        constraintUpdatePublisher.send(.reset)
    }

    /// Removes the pill controller
    @MainActor
    private func removePillContainer() {
        // First remove from superview
        containerViewController?.view.removeFromSuperview()

        // Then clean up references
        containerViewController = nil
        containerViewModel = nil
        presentedPillType = nil
        containerCancellables.removeAll()

        // Finally ensure constraints are reset
        resetWebViewConstraint()
    }

    deinit {
        cleanupPlayer()
        containerCancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func cleanupPlayer() {
        playerCancellables.removeAll()
        playerViewModel = nil
    }

    @MainActor
    private func displayToast(with message: AttributedString, buttonTitle: String, onButtonTapped: (() -> Void)?) {
        DuckPlayerToastView.present(
            message: message,
            buttonTitle: buttonTitle,
            onButtonTapped: onButtonTapped
        )
    }

    @MainActor
    private func presentDismissCountToast() {
        var message = AttributedString(UserText.duckPlayerToastTurnOffAnytime)
        message.foregroundColor = .white
        displayToast(
            with: message,
            buttonTitle: UserText.duckPlayerToastOpenSettings
        ) {
            NotificationCenter.default.post(
                name: .settingsDeepLinkNotification,
                object: SettingsViewModel.SettingsDeepLinkSection.duckPlayer,
                userInfo: nil
            )
        }
    }

    /// Posts a notification about the pill's visibility state
    private func postPillVisibilityNotification(isVisible: Bool) {
        notificationCenter.post(
            name: Notifications.duckPlayerPillUpdated,
            object: nil,
            userInfo: [
                NotificationKeys.isVisible: isVisible
            ]
        )
    }

    /// Fires DuckPlayer presentation pixels
    private func fireDuckPlayerPresentationPixels(for source: DuckPlayer.VideoNavigationSource) {

        // Daily Pixel
        let setting = duckPlayerSettings.nativeUIYoutubeMode == .auto ? "auto" : "ask"
        let toggle = duckPlayerSettings.duckPlayerControlsVisible ? "visible" : "hidden"
        let parameters: [String: String] = [
            "setting": setting,
            "toggle": toggle
        ]
        pixelHandler.fireDaily(.duckPlayerNativeDailyUniqueView, withAdditionalParameters: parameters)

        if source == .youtube {
            switch duckPlayerSettings.nativeUIYoutubeMode {
            case .auto:
                pixelHandler.fire(.duckPlayerNativeViewFromYoutubeAutomatic)
            case .ask:
                switch presentedPillType {
                case .entry:
                    pixelHandler.fire(.duckPlayerNativeViewFromYoutubeEntryPoint)
                case .reEntry:
                    pixelHandler.fire(.duckPlayerNativeViewFromYoutubeReEntryPoint)
                case .welcome:
                    pixelHandler.fire(.duckPlayerNativePrimingModalCTA)
                case .none:
                    break
                }
            case .never:
                break
            }
        }

        if source == .serp {
            pixelHandler.fire(.duckPlayerNativeViewFromSERP)
        }

    }

    /// Fires Pill Dismissal pixels
    private func fireDuckPlayerDismissalPixels(for pillType: PillType) {
            switch presentedPillType {
            case .welcome:
                pixelHandler.fire(.duckPlayerNativePrimingModalDismissed)
            case .entry:
                pixelHandler.fire(.duckPlayerNativeEntryPointDismissed)
            case .reEntry:
                pixelHandler.fire(.duckPlayerNativeReEntryPointDismissed)
            default:
                break
            }
    }

    /// Fires pill impression pixels
    private func firePillImpressionPixels(for pillType: PillType) {
        switch pillType {
        case .welcome:
            if duckPlayerSettings.nativeUIYoutubeMode == .ask {
                pixelHandler.fire(.duckPlayerNativePrimingModalImpression)
            }
        case .entry:
            if duckPlayerSettings.nativeUIYoutubeMode == .ask {
                pixelHandler.fire(.duckPlayerNativeEntryPointImpression)
            }
        case .reEntry:
            // Re-entry is shown in both .ask and .auto modes
            pixelHandler.fire(.duckPlayerNativeReEntryPointImpression)
        }
    }

}

extension DuckPlayerNativeUIPresenter: DuckPlayerNativeUIPresenting {
    
    /// Presents a bottom pill asking the user how they want to open the video
    ///
    /// - Parameters:
    ///   - videoID: The YouTube video ID to be played
    ///   - timestamp: The timestamp of the video
    @MainActor
    func presentPill(for videoID: String, in hostViewController: DuckPlayerHosting, timestamp: TimeInterval?) {
        // Store the videoID & Update State
        if state.videoID != videoID {
            state.hasBeenShown = false
            state.videoID = videoID
            presentedPillType = nil
        }

        // If the welcome pill is already presented, don't show the entry pill
        if presentedPillType == .welcome {
            return
        }

        // Determine the pill type
        let pillType: PillType

        // If primingModalEventCount is 0, show the welcome pill for first-time users
        if !duckPlayerSettings.primingMessagePresented {
            pillType = .welcome
          self.duckPlayerSettings.primingMessagePresented = true
        } else {
            // Logic for returning users
            pillType = state.hasBeenShown ? .reEntry : .entry
        }

        presentedPillType = pillType

        // Fire pill impression pixels
        firePillImpressionPixels(for: pillType)

        // If no specific timestamp is provided, use the current stave value
        let timestamp = timestamp ?? state.timestamp ?? 0

        // If we already have a container view model, just update the content and show it again
        if let existingViewModel = containerViewModel, let hostingController = containerViewController {
            updatePillContent(for: pillType, videoID: videoID, timestamp: timestamp, in: hostingController)
            pillHeight = Constants.webViewRequiredBottomConstraint
            existingViewModel.show()
            postPillVisibilityNotification(isVisible: true)
            return
        }

        self.hostView = hostViewController
        guard let hostView = self.hostView else { return }

        // Create and configure the container view model
        let containerViewModel = DuckPlayerContainer.ViewModel()
        self.containerViewModel = containerViewModel

        // Initialize a generic container
        var containerView: DuckPlayerContainer.Container<AnyView>

        // Create the container view with the appropriate pill view
        containerView = createContainerWithPill(for: pillType, videoID: videoID, timestamp: timestamp, containerViewModel: containerViewModel)

        // Set up hosting controller
        let hostingController = UIHostingController(rootView: containerView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.modalPresentationStyle = .overCurrentContext
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        // Add to host view
        hostView.view.addSubview(hostingController.view)

        // Calculate bottom constraints based on URL Bar position
        // If at the bottom, the Container should be placed above it
        bottomConstraint =
            appSettings.currentAddressBarPosition == .bottom
            ? hostingController.view.bottomAnchor.constraint(equalTo: hostView.view.bottomAnchor, constant: -omniBarHeight)
            : hostingController.view.bottomAnchor.constraint(equalTo: hostView.view.bottomAnchor)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: hostView.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: hostView.view.trailingAnchor),
            bottomConstraint!
        ])

        // Store reference to the hosting controller
        containerViewController = hostingController

        // Subscribe to the sheet animation completed event
        containerViewModel.$sheetAnimationCompleted.sink { [weak self] completed in
            if completed && containerViewModel.sheetVisible {
                self?.updateWebViewConstraintForPillHeight()
            }
        }.store(in: &containerCancellables)

        // Subscribe to dragging state changes
        containerViewModel.$isDragging.sink { [weak self] isDragging in
            if isDragging {
                self?.resetWebViewConstraint()
            } else if containerViewModel.sheetVisible {
                self?.updateWebViewConstraintForPillHeight()
            }
        }.store(in: &containerCancellables)

        // Show the container view if it's not already visible
        if !containerViewModel.sheetVisible {
            containerViewModel.show()
            postPillVisibilityNotification(isVisible: true)
        }
    }

    /// Dismisses the currently presented entry pill
    @MainActor
    func dismissPill(reset: Bool = false, animated: Bool = true, programatic: Bool = true) {
        // First reset constraints immediately
        resetWebViewConstraint()

        postPillVisibilityNotification(isVisible: false)

        // Check if this is a welcome pill being dismissed
        let wasWelcomePill = !duckPlayerSettings.primingMessagePresented

        // If was dismissed by the user, increment the dismiss count
        if !programatic {
            duckPlayerSettings.pillDismissCount += 1

            // Fire pill dismissal pixels
            if let presentedPillType = presentedPillType {
                fireDuckPlayerDismissalPixels(for: presentedPillType)
            }

            if duckPlayerSettings.pillDismissCount == 3 {
                // Present toast reminding the user that they can disable DuckPlayer in settings
                presentDismissCountToast()
            }
        }

        // Then dismiss the view model
        containerViewModel?.dismiss()

        // Function to handle welcome pill transition
        let handleWelcomePillTransition = { [weak self] in
            guard let self = self,
                  wasWelcomePill,
                  let videoID = self.state.videoID,
                  let hostView = self.hostView else { return }

            self.presentPill(for: videoID, in: hostView, timestamp: self.state.timestamp)
        }

        if animated {
            // Remove the view after the animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.removePillContainer()
                handleWelcomePillTransition()
            }
        } else {
            removePillContainer()
            handleWelcomePillTransition()
        }

        if reset {
            self.state = DuckPlayerState()
        }
    }

    @MainActor
    func presentDuckPlayer(
        videoID: String, source: DuckPlayer.VideoNavigationSource, in hostViewController: DuckPlayerHosting, title: String?, timestamp: TimeInterval?
    ) -> (navigation: PassthroughSubject<URL, Never>, settings: PassthroughSubject<Void, Never>) {

        // Reset the dismiss count if toast not already presented
        if duckPlayerSettings.pillDismissCount < 3 {
            duckPlayerSettings.pillDismissCount = 0
        }

        // Create publishers for Youtube Navigation & Settings
        // Fire pixels as needed
        fireDuckPlayerPresentationPixels(for: source)

        let navigationRequest = PassthroughSubject<URL, Never>()
        let settingsRequest = PassthroughSubject<Void, Never>()

        // Emit a signal about presenting the full player
        presentDuckPlayerRequest.send()

        let viewModel = DuckPlayerViewModel(videoID: videoID, timestamp: timestamp, source: source)
        self.playerViewModel = viewModel  // Keep strong reference

        let webView = DuckPlayerWebView(viewModel: viewModel)
        let duckPlayerView = DuckPlayerView(viewModel: viewModel, webView: webView)

        let hostingController = UIHostingController(rootView: duckPlayerView)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.isModalInPresentation = false

        // Update State
        self.state.hasBeenShown = true

        // Reset the presented pill type as we are transitioning to the full player
        self.presentedPillType = nil

        // Subscribe to Navigation Request Publisher
        viewModel.youtubeNavigationRequestPublisher
            .sink { [weak self, weak hostingController] videoID in
                if source != .youtube {
                    let url: URL = .youtube(videoID)
                    navigationRequest.send(url)
                }

                Task { @MainActor in
                    await withCheckedContinuation { continuation in
                        hostingController?.dismiss(animated: true) {
                            continuation.resume()
                        }
                    }
                    // Clean up after navigation away
                    self?.cleanupPlayer()
                }
            }
            .store(in: &playerCancellables)

        // Subscribe to Settings Request Publisher
        viewModel.settingsRequestPublisher
            .sink { settingsRequest.send() }
            .store(in: &playerCancellables)

        // General Dismiss Publisher
        viewModel.dismissPublisher
            .sink { [weak self] timestamp in
                guard let self = self else { return }
                guard let videoID = self.state.videoID, let hostView = self.hostView else { return }
                self.state.timestamp = timestamp
                self.duckPlayerSettings.welcomeMessageShown = true
                
                // Notify DuckPlayer to store this timestamp for re-entry pills
                self.duckPlayerTimestampUpdate.send(timestamp)
                
                // Schedule pill presentation after a short delay to ensure view is dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.presentPill(for: videoID, in: hostView, timestamp: timestamp)
                    self.containerViewModel?.show()
                }
            }
            .store(in: &playerCancellables)

        hostViewController.present(hostingController, animated: true, completion: nil)

        // Dismiss the Pill (but don't reset state as we may need to show it again)
        dismissPill(reset: false)

        return (navigationRequest, settingsRequest)
    }

    /// Hides the bottom sheet when browser chrome is hidden
    @MainActor
    func hideBottomSheetForHiddenChrome() {
        containerViewModel?.dismiss()
        resetWebViewConstraint()
        containerViewController?.view.isUserInteractionEnabled = false
         postPillVisibilityNotification(isVisible: false)
    }

    /// Shows the bottom sheet when browser chrome is visible
    @MainActor
    func showBottomSheetForVisibleChrome() {
        containerViewModel?.show()
        containerViewController?.view.isUserInteractionEnabled = true
        postPillVisibilityNotification(isVisible: true)
    }

}
