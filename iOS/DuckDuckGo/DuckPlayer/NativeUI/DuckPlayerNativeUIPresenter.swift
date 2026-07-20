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
    @MainActor func dismissPill(reset: Bool, animated: Bool, programatic: Bool, skipTransition: Bool)
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

        // Fallback clearance for the floating toolbar if the host hasn't reported a bar height yet.
        static let floatingToolbarClearance: CGFloat = BrowserToolbarView.floatingButtonsHeight + 21

        // Max time to wait for the floating pill thumbnail before sliding in anyway.
        static let thumbnailReadyTimeout: TimeInterval = 1.0

        // persistentBottomBarHeight is the full safe-area-anchored bar region, but the visible floating
        // capsule floats lower than that region's top. Trim this much so the pill sits just above the
        // capsule rather than the (taller) logical bar region. Tuned against device runtime numbers.
        static let floatingCapsuleInset: CGFloat = 20
    }

    /// The container view model for the entry pill
    private(set) var containerViewModel: DuckPlayerContainer.ViewModel?

    /// The hosting controller for the container
    private(set) var containerViewController: UIHostingController<DuckPlayerContainer.Container<AnyView>>?

    /// References to the host view and source
    internal weak var hostView: DuckPlayerHosting?
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

    /// Readiness signal for the floating pill thumbnail; set while building a floating pill and
    /// consumed to gate the slide-in so the pill and its thumbnail animate in together.
    @MainActor private var pendingThumbnailReady: AnyPublisher<Bool, Never>?
    @MainActor private var thumbnailReadyCancellable: AnyCancellable?
    @MainActor private var thumbnailReadyTimeoutWorkItem: DispatchWorkItem?

    // Other cancellables
    private var cancellables = Set<AnyCancellable>()

    /// Application Settings
    private var appSettings: AppSettings

    /// DuckPlayer Settings
    internal var duckPlayerSettings: DuckPlayerSettings


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

    // Content Scripts dependencies
    private let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies

    // Pixel Handler
    let pixelHandler: DuckPlayerPixelFiring.Type

    /// When enabled, the entry and re-entry pills use the black floating design.
    private let floatingUIManager: FloatingUIManaging

    // MARK: - Public Methods
    ///
    /// - Parameter appSettings: The application settings
    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         duckPlayerSettings: DuckPlayerSettings = DuckPlayerSettingsDefault(),
         state: DuckPlayerState = DuckPlayerState(),
         notificationCenter: NotificationCenter = .default,
         userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
         pixelHandler: DuckPlayerPixelFiring.Type = DuckPlayerPixelHandler.self,
         floatingUIManager: FloatingUIManaging = FloatingUIManager()) {
        self.appSettings = appSettings
        self.duckPlayerSettings = duckPlayerSettings
        self.state = state
        self.notificationCenter = notificationCenter
        self.pixelHandler = pixelHandler
        self.userScriptsDependencies = userScriptsDependencies
        self.floatingUIManager = floatingUIManager
        setupNotificationObservers(notificationCenter: notificationCenter)
    }
    

    /// Sets up notification observers for address bar position changes    
    private func setupNotificationObservers(notificationCenter: NotificationCenter) {
        // Listen for address bar position changes to update pill positioning        
        notificationCenter.publisher(for: AppUserDefaults.Notifications.addressBarPositionChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePillBottomConstraint()
            }
            .store(in: &cancellables)

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

    
    /// Floating UI: sit above the whole bottom chrome using the host's bar height. Otherwise: above
    /// the address bar when it's at the bottom, at screen bottom when it's at the top.
    private var pillBottomConstraintConstant: CGFloat {
        if floatingUIManager.isFloatingUIEnabled {
            let barHeight = hostView?.persistentBottomBarHeight ?? Constants.floatingToolbarClearance
            return -(barHeight - Constants.floatingCapsuleInset)
        }
        return appSettings.currentAddressBarPosition == .bottom ? -DefaultOmniBarView.expectedHeight : 0
    }

    /// Updates the pill's bottom constraint based on the current address bar position
    private func updatePillBottomConstraint() {
        guard let bottomConstraint = self.bottomConstraint else { return }
        bottomConstraint.constant = pillBottomConstraintConstant
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
            let welcomePillViewModel = DuckPlayerWelcomePillViewModel(
                onOpen: { [weak self] in
                    self?.videoPlaybackRequest.send((videoID, timestamp, .welcome))
                },
                onClose: { [weak self] in
                    self?.dismissPill(programatic: false)
                }
            )

            // Create the container view with the welcome pill
            return DuckPlayerContainer.Container(
                viewModel: containerViewModel,
                hasBackground: false,
                showDragHandle: false,
                allowDragGesture: false,
                onDismiss: { [weak self] programatic in
                    self?.dismissPill(programatic: programatic)
                },
                onPresentDuckPlayer: { [weak self] in
                    guard let self = self,
                          let hostView = self.hostView else { return }
                    _ = self.presentDuckPlayer(
                        videoID: videoID,
                        source: .youtube,
                        in: hostView,
                        title: nil,
                        timestamp: timestamp
                    )
                }
            ) { _ in
                AnyView(DuckPlayerWelcomePillView(viewModel: welcomePillViewModel))
            }
        } else if pillType == .entry {
            let useFloatingStyle = floatingUIManager.isFloatingUIEnabled

            // videoID is only needed to fetch the thumbnail used by the floating design.
            let pillViewModel = DuckPlayerEntryPillViewModel(videoID: useFloatingStyle ? videoID : nil) { [weak self] in
                self?.videoPlaybackRequest.send((videoID, timestamp, .entry))
            }

            // Floating pill waits for the thumbnail before sliding in so it animates as one unit.
            if useFloatingStyle {
                pendingThumbnailReady = pillViewModel.$thumbnailImage.map { $0 != nil }.eraseToAnyPublisher()
            }

            // Create the container view with the pill view
            return DuckPlayerContainer.Container(
                viewModel: containerViewModel,
                hasBackground: false,
                showDragHandle: !useFloatingStyle,
                floatingStyle: useFloatingStyle,
                onDismiss: { [weak self] programatic in
                    self?.dismissPill(programatic: programatic)
                },
                onPresentDuckPlayer: { [weak self] in
                    guard let self = self,
                          let hostView = self.hostView else { return }
                    _ = self.presentDuckPlayer(
                        videoID: videoID,
                        source: .youtube,
                        in: hostView,
                        title: nil,
                        timestamp: timestamp
                    )
                }
            ) { _ in
                AnyView(
                    Group {
                        if useFloatingStyle {
                            DuckPlayerFloatingEntryPillView(viewModel: pillViewModel)
                        } else {
                            DuckPlayerEntryPillView(viewModel: pillViewModel)
                        }
                    }
                )
            }
        } else {
            let useFloatingStyle = floatingUIManager.isFloatingUIEnabled

            // Create the mini pill view model for re-entry type
            let miniPillViewModel = DuckPlayerMiniPillViewModel(
                onOpen: { [weak self] in
                    self?.videoPlaybackRequest.send((videoID, timestamp, .reEntry))
                },
                videoID: videoID,
                loadsThumbnailImage: useFloatingStyle
            )

            // Floating pill waits for the thumbnail before sliding in so it animates as one unit.
            if useFloatingStyle {
                pendingThumbnailReady = miniPillViewModel.$thumbnailImage.map { $0 != nil }.eraseToAnyPublisher()
            }

            // Create the container view with the mini pill view
            return DuckPlayerContainer.Container(
                viewModel: containerViewModel,
                hasBackground: false,
                showDragHandle: !useFloatingStyle,
                floatingStyle: useFloatingStyle,
                onDismiss: { [weak self] programatic in
                    self?.dismissPill(programatic: programatic)
                },
                onPresentDuckPlayer: { [weak self] in
                    guard let self = self,
                          let hostView = self.hostView else { return }
                    _ = self.presentDuckPlayer(
                        videoID: videoID,
                        source: .youtube,
                        in: hostView,
                        title: nil,
                        timestamp: timestamp
                    )
                }
            ) { _ in
                AnyView(
                    Group {
                        if useFloatingStyle {
                            DuckPlayerFloatingMiniPillView(viewModel: miniPillViewModel)
                        } else {
                            DuckPlayerMiniPillView(viewModel: miniPillViewModel)
                        }
                    }
                )
            }
        }
    }

    /// Updates the webView constraint based on the current pill height
    @MainActor
    private func updateWebViewConstraintForPillHeight() {
        guard hostView != nil else { return }
        // Floating UI content is full-bleed under the glass, so the pill overlays it instead of resizing it.
        guard !floatingUIManager.isFloatingUIEnabled else { return }
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
        guard hostView != nil else { return }
        constraintUpdatePublisher.send(.reset)
    }

    /// Removes the pill controller
    @MainActor
    private func removePillContainer() {
        // Cancel all subscriptions first
        cancelPendingPillReveal()
        containerCancellables.removeAll()
        
        // Remove constraints before removing from superview
        bottomConstraint?.isActive = false
        bottomConstraint = nil
        
        // First remove from superview
        containerViewController?.view.removeFromSuperview()

        // Then clean up references
        containerViewController = nil
        containerViewModel = nil
        presentedPillType = nil

        // Finally ensure constraints are reset
        resetWebViewConstraint()
    }

    deinit {
        // Cancel all subscriptions
        cancellables.removeAll()
        containerCancellables.removeAll()
        playerCancellables.removeAll()
        
        // Clean up player
        cleanupPlayer()
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        
        // Clean up any remaining UI elements
        bottomConstraint?.isActive = false
        bottomConstraint = nil
        containerViewController?.view.removeFromSuperview()
        containerViewController = nil
        containerViewModel = nil
    }
    
    internal func cleanupPlayer() {
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
    // swiftlint:disable:next cyclomatic_complexity
    func presentPill(for videoID: String, in hostViewController: DuckPlayerHosting, timestamp: TimeInterval?) {

        if duckPlayerSettings.nativeUIYoutubeMode == .never {
            return
        }
        
        // Check if webView exists and has a non-YouTube watch URL
        if let webView = hostViewController.webView, let url = webView.url, !url.isYoutubeWatch {
            return
        }

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

        // If no specific timestamp is provided, use the current state value
        let timestamp = timestamp ?? state.timestamp ?? 0

        // If we already have a container view model, just update the content and show it again
        if let existingViewModel = containerViewModel, let hostingController = containerViewController {
            updatePillContent(for: pillType, videoID: videoID, timestamp: timestamp, in: hostingController)
            pillHeight = Constants.webViewRequiredBottomConstraint
            // Re-presentation of an existing pill shows immediately (no thumbnail wait).
            pendingThumbnailReady = nil
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

        // Position the pill above the bottom chrome (see pillBottomConstraintConstant).
        let newBottomConstraint = hostingController.view.bottomAnchor.constraint(
            equalTo: hostView.view.bottomAnchor,
            constant: pillBottomConstraintConstant)

        bottomConstraint = newBottomConstraint

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: hostView.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: hostView.view.trailingAnchor),
            newBottomConstraint
        ])

        // Store reference to the hosting controller
        containerViewController = hostingController
        
        // Initialize pill position based on current address bar position
        // This ensures the pill is positioned correctly on first presentation
        updatePillBottomConstraint()

        // Subscribe to the sheet animation completed event
        containerViewModel.$sheetAnimationCompleted.sink { [weak self, weak containerViewModel] completed in
            guard let self = self,
                  let containerViewModel = containerViewModel,
                  completed && containerViewModel.sheetVisible else { return }
            self.updateWebViewConstraintForPillHeight()
        }.store(in: &containerCancellables)

        // Subscribe to dragging state changes
        containerViewModel.$isDragging.sink { [weak self, weak containerViewModel] isDragging in
            guard let self = self,
                  let containerViewModel = containerViewModel else { return }
            
            if isDragging {
                self.resetWebViewConstraint()
            } else if containerViewModel.sheetVisible {
                self.updateWebViewConstraintForPillHeight()
            }
        }.store(in: &containerCancellables)

        // Show the container view if it's not already visible
        if !containerViewModel.sheetVisible {
            showPillWhenReady(containerViewModel)
        }
    }

    /// Shows the pill immediately, unless a floating thumbnail is still loading — then it waits for
    /// the image (or a timeout) so the pill and its thumbnail slide in together.
    @MainActor
    private func showPillWhenReady(_ viewModel: DuckPlayerContainer.ViewModel) {
        let ready = pendingThumbnailReady
        pendingThumbnailReady = nil

        // Drop any prior pending reveal so a stale subscription/timeout can't fire later.
        cancelPendingPillReveal()

        guard let ready else {
            viewModel.show()
            postPillVisibilityNotification(isVisible: true)
            return
        }

        var didShow = false
        let show: () -> Void = { [weak self, weak viewModel] in
            guard !didShow, let self, let viewModel else { return }
            didShow = true
            self.cancelPendingPillReveal()
            viewModel.show()
            self.postPillVisibilityNotification(isVisible: true)
        }

        thumbnailReadyCancellable = ready
            .filter { $0 }
            .prefix(1)
            .receive(on: DispatchQueue.main)
            .sink { _ in show() }

        // Timeout fallback so a slow/failed image never blocks the pill. Cancellable so a dismiss
        // mid-load doesn't later revive the pill.
        let timeout = DispatchWorkItem { show() }
        thumbnailReadyTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.thumbnailReadyTimeout, execute: timeout)
    }

    /// Cancels a scheduled floating-pill reveal (thumbnail subscription + timeout) so it can't fire
    /// after the pill has been dismissed or torn down.
    @MainActor
    private func cancelPendingPillReveal() {
        thumbnailReadyCancellable = nil
        thumbnailReadyTimeoutWorkItem?.cancel()
        thumbnailReadyTimeoutWorkItem = nil
        pendingThumbnailReady = nil
    }

    /// Dismisses the currently presented entry pill
    @MainActor
    func dismissPill(reset: Bool = false, animated: Bool = true, programatic: Bool = true, skipTransition: Bool = false) {
        // Cancel any pending thumbnail-gated reveal so it can't re-show the pill after dismissal.
        cancelPendingPillReveal()

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
                  !skipTransition,
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

        // Store the host view reference for potential pill re-presentation after dismissal
        self.hostView = hostViewController
        
        // Update state with videoID
        self.state.videoID = videoID
        
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

        let webView = DuckPlayerWebView(viewModel: viewModel,
                                        scriptSourceProviderDependencies: userScriptsDependencies)
        let duckPlayerView = DuckPlayerView(viewModel: viewModel, webView: webView)

        let hostingController = UIHostingController(rootView: duckPlayerView)
        hostingController.view.backgroundColor = UIColor.black

        let roundedSheetController = RoundedPageSheetContainerViewController(contentViewController: hostingController)

        // Update State
        self.state.hasBeenShown = true

        // Reset the presented pill type as we are transitioning to the full player
        self.presentedPillType = nil

        // Subscribe to Navigation Request Publisher
        viewModel.youtubeNavigationRequestPublisher
            .sink { [weak self, weak roundedSheetController] url in
                navigationRequest.send(url)

                Task { @MainActor in
                    await withCheckedContinuation { continuation in
                        roundedSheetController?.dismiss(animated: true) {
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
                guard let self = self,
                      self.hostView != nil,
                      self.state.videoID != nil else { return }

                // Update state and settings only when we have a valid hostView
                self.state.timestamp = timestamp
                self.duckPlayerSettings.welcomeMessageShown = true

                // Notify DuckPlayer to store this timestamp for re-entry pills
                self.duckPlayerTimestampUpdate.send(timestamp)

                // Schedule pill presentation after a short delay to ensure view is dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self,
                          let hostView = self.hostView,
                          let currentVideoID = self.state.videoID else { return }

                    self.presentPill(for: currentVideoID, in: hostView, timestamp: timestamp)
                    self.containerViewModel?.show()
                }
            }
            .store(in: &playerCancellables)

        hostViewController.present(roundedSheetController, animated: true, completion: nil)

        // Dismiss the Pill immediately (but don't reset state as we may need to show it again)
        dismissPill(reset: false, animated: false, programatic: true, skipTransition: true)

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
