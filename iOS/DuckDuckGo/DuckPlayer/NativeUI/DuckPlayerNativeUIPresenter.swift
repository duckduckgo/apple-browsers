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

import Foundation
import UIKit
import SwiftUI
import Combine

protocol DuckPlayerNativeUIPresenting {

    var videoPlaybackRequest: PassthroughSubject<String, Never> { get }

    @MainActor func presentPill(for videoID: String, in hostViewController: TabViewController, timestamp: String?)
    @MainActor func dismissPill(reset: Bool)
    @MainActor func presentDuckPlayer(videoID: String, source: DuckPlayer.VideoNavigationSource, in hostViewController: TabViewController, title: String?, timestamp: String?) -> (navigation: PassthroughSubject<URL, Never>, settings: PassthroughSubject<Void, Never>)
    @MainActor func showBottomSheetForVisibleChrome()
    @MainActor func hideBottomSheetForHiddenChrome()
}

/// A presenter class responsible for managing the native UI components of DuckPlayer.
/// This includes presenting entry pills and handling their lifecycle.
final class DuckPlayerNativeUIPresenter {

    /// The types of the pill available
    enum PillType {
        case entry
        case reEntry
    }

    struct Constants {
        // Used to update the WebView's bottom constraint
        // When pill is visible
        static let webViewRequiredBottomConstraint: CGFloat = 90
    }

    /// The container view model for the entry pill
    private var containerViewModel: DuckPlayerContainer.ViewModel?

    /// The hosting controller for the container
    private var containerViewController: UIHostingController<DuckPlayerContainer.Container<AnyView>>?

    /// References to the host view and source
    private weak var hostView: TabViewController?
    private var source: DuckPlayer.VideoNavigationSource?
    private var state: DuckPlayerState

    /// The DuckPlayer instance
    private weak var duckPlayer: DuckPlayerControlling?

    /// The view model for the player
    private var playerViewModel: DuckPlayerViewModel?

    /// A publisher to notify when a video playback request is needed
    let videoPlaybackRequest = PassthroughSubject<String, Never>()
    private var playerCancellables = Set<AnyCancellable>()
    private var containerCancellables = Set<AnyCancellable>()

    /// Application Settings
    private var appSettings: AppSettings

    /// Current height of the OmniBar
    private var omniBarHeight: CGFloat = 0

    /// Bottom constraint for the container view
    private var bottomConstraint: NSLayoutConstraint?

    /// Height of the current pill view
    private var pillHeight: CGFloat = 0

    // MARK: - Public Methods
    ///
    /// - Parameter appSettings: The application settings
    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings, state: DuckPlayerState = DuckPlayerState()) {
        self.appSettings = appSettings
        self.state = state
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleOmnibarDidLayout),
                                               name: OmniBar.didLayoutNotification,
                                               object: nil)
    }

    /// Updates the UI based on Ombibar Notification
    @objc private func handleOmnibarDidLayout(_ notification: Notification) {
        guard let omniBar = notification.object as? OmniBar else { return }
        omniBarHeight = omniBar.frame.height
        guard let bottomConstraint = bottomConstraint else { return }
        bottomConstraint.constant = appSettings.currentAddressBarPosition == .bottom ? -omniBarHeight : 0
    }

    /// Creates a container with the appropriate pill view based on the pill type
    @MainActor
    private func createContainerWithPill(for pillType: PillType, videoID: String, containerViewModel: DuckPlayerContainer.ViewModel) -> DuckPlayerContainer.Container<AnyView> {

        // Set pill height based on type
        pillHeight = Constants.webViewRequiredBottomConstraint

        if pillType == .entry {
            // Create the pill view model for entry type
            let pillViewModel = DuckPlayerEntryPillViewModel { [weak self] in
                self?.videoPlaybackRequest.send(videoID)
            }

            // Create the container view with the pill view
            return DuckPlayerContainer.Container(
                viewModel: containerViewModel,
                hasBackground: false
            ) { _ in
                AnyView(DuckPlayerEntryPillView(viewModel: pillViewModel))
            }
        } else {
            // Create the mini pill view model for re-entry type
            let miniPillViewModel = DuckPlayerMiniPillViewModel(onOpen: { [weak self] in
                self?.videoPlaybackRequest.send(videoID)
            }, videoID: videoID)

            // Create the container view with the mini pill view
            return DuckPlayerContainer.Container(
                viewModel: containerViewModel,
                hasBackground: false
            ) { _ in
                AnyView(DuckPlayerMiniPillView(viewModel: miniPillViewModel))
            }
        }
    }

    /// Updates the webView constraint based on the current pill height
    @MainActor
    private func updateWebViewConstraintForPillHeight() {

        if let hostView = self.hostView, let webViewBottomConstraint = hostView.webViewBottomAnchorConstraint {
            if self.appSettings.currentAddressBarPosition == .bottom {
                let targetHeight = hostView.chromeDelegate?.barsMaxHeight ?? 0.0
                webViewBottomConstraint.constant = -targetHeight - self.pillHeight
            } else {
                webViewBottomConstraint.constant = -self.pillHeight
            }
            hostView.view.layoutIfNeeded()
        }
    }

    /// Updates the content of an existing hosting controller with the appropriate pill view
    @MainActor
    private func updatePillContent(for pillType: PillType, videoID: String, in hostingController: UIHostingController<DuckPlayerContainer.Container<AnyView>>) {
        guard let containerViewModel = self.containerViewModel else { return }

        // Create a new container with the updated content
        let updatedContainer = createContainerWithPill(for: pillType, videoID: videoID, containerViewModel: containerViewModel)

        // Update the hosting controller's root view
        hostingController.rootView = updatedContainer
    }

    /// Resets the webView constraint to its default value
    @MainActor
    private func resetWebViewConstraint() {
        if let hostView = self.hostView, let webViewBottomConstraint = hostView.webViewBottomAnchorConstraint {

            // Reset to the default value based on address bar position
            let targetHeight = hostView.chromeDelegate?.barsMaxHeight ?? 0.0
            webViewBottomConstraint.constant = appSettings.currentAddressBarPosition == .bottom ? -targetHeight : 0

            hostView.view.layoutIfNeeded()
        }
    }

    deinit {
        playerCancellables.removeAll()
        containerCancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}

extension DuckPlayerNativeUIPresenter: DuckPlayerNativeUIPresenting {

    /// Presents a bottom pill asking the user how they want to open the video
    ///
    /// - Parameters:
    ///   - videoID: The YouTube video ID to be played
    ///   - timestamp: The timestamp of the video
    @MainActor
    func presentPill(for videoID: String, in hostViewController: TabViewController, timestamp: String?) {

        // Store the videoID & Update State
        if state.videoID != videoID {
            state.hasBeenShown = false
            state.videoID = videoID
        }

        // Determine the pill type
        let pillType: PillType = state.hasBeenShown ? .reEntry : .entry

        // If we already have a container view model, just update the content and show it again
        if let existingViewModel = containerViewModel, let hostingController = containerViewController {
            updatePillContent(for: pillType, videoID: videoID, in: hostingController)
            pillHeight = Constants.webViewRequiredBottomConstraint
            existingViewModel.show()
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
        containerView = createContainerWithPill(for: pillType, videoID: videoID, containerViewModel: containerViewModel)

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
        bottomConstraint = appSettings.currentAddressBarPosition == .bottom ?
                    hostingController.view.bottomAnchor.constraint(equalTo: hostView.view.bottomAnchor, constant: -omniBarHeight) :
                    hostingController.view.bottomAnchor.constraint(equalTo: hostView.view.bottomAnchor)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: hostView.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: hostView.view.trailingAnchor),
            bottomConstraint!
        ])

        // Store reference to the hosting controller
        containerViewController = hostingController
        containerViewModel.show()

        // Subscribe to the sheet animation completed event
        containerViewModel.$sheetAnimationCompleted.sink { [weak self] completed in
            if completed && containerViewModel.sheetVisible {
                    self?.updateWebViewConstraintForPillHeight()
            }
        }.store(in: &containerCancellables)

    }

    /// Dismisses the currently presented entry pill
    @MainActor
    func dismissPill(reset: Bool = false) {
        containerViewModel?.dismiss()
        resetWebViewConstraint()

        // Remove the view after the animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.containerViewController?.view.removeFromSuperview()
            self?.containerViewController = nil
            self?.containerViewModel = nil
            self?.containerCancellables.removeAll()
        }

        if reset {
            self.state = DuckPlayerState()
        }
    }

    @MainActor
    func presentDuckPlayer(videoID: String, source: DuckPlayer.VideoNavigationSource, in hostViewController: TabViewController, title: String?, timestamp: String?) -> (navigation: PassthroughSubject<URL, Never>, settings: PassthroughSubject<Void, Never>) {
        let navigationRequest = PassthroughSubject<URL, Never>()
        let settingsRequest = PassthroughSubject<Void, Never>()

        let viewModel = DuckPlayerViewModel(videoID: videoID)
        self.playerViewModel = viewModel // Keep strong reference

        let webView = DuckPlayerWebView(viewModel: viewModel)
        let duckPlayerView = DuckPlayerView(viewModel: viewModel, webView: webView)

        let hostingController = UIHostingController(rootView: duckPlayerView)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.isModalInPresentation = false

        // Update State        
        self.state.hasBeenShown = true

        // Subscribe to Navigation Request Publisher
        viewModel.youtubeNavigationRequestPublisher
            .sink { [weak hostingController] videoID in
                if source != .youtube {
                    let url: URL = .youtube(videoID)
                    navigationRequest.send(url)
                }
                hostingController?.dismiss(animated: true)
            }
            .store(in: &playerCancellables)

        // Subscribe to Settings Request Publisher
        viewModel.settingsRequestPublisher
            .sink { settingsRequest.send() }
            .store(in: &playerCancellables)

        // General Dismiss Publisher
        viewModel.dismissPublisher
            .sink { [weak self] in
                guard let self = self else { return }
                guard let videoID = self.state.videoID, let hostView = self.hostView else { return }
                self.presentPill(for: videoID, in: hostView, timestamp: nil)
            }
            .store(in: &playerCancellables)

        hostViewController.present(hostingController, animated: true)

        // Dismiss the Pill
        dismissPill()

        return (navigationRequest, settingsRequest)
    }

    /// Hides the bottom sheet when browser chrome is hidden
    @MainActor
    func hideBottomSheetForHiddenChrome() {
        containerViewModel?.dismiss()
        resetWebViewConstraint()
    }

    /// Shows the bottom sheet when browser chrome is visible
    @MainActor
    func showBottomSheetForVisibleChrome() {
        containerViewModel?.show()
    }

}
