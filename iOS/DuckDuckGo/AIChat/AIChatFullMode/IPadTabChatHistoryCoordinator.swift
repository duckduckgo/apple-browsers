//
//  IPadTabChatHistoryCoordinator.swift
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

import AIChat
import Combine
import DesignResourcesKit
import PrivacyConfig
import UIComponents
import UIKit

/// Coordinates the AI chat history list displayed below the expanded omnibar in iPad tab mode.
@MainActor
final class IPadTabChatHistoryCoordinator {

    // MARK: - Constants

    private enum Layout {
        static let cornerRadius: CGFloat = 16
        static let topSpacing: CGFloat = 15
        static let widthPadding: CGFloat = 0
        /// Matches `AIChatHistoryListViewController.Constants.cellHeight`.
        static let cellHeight: CGFloat = 44
        /// Extra vertical padding to account for the `.insetGrouped` table style's
        /// built-in section insets (top/bottom rounded-corner area) minus the negative
        /// content inset applied by AIChatHistoryListViewController.
        static let groupedSectionPadding: CGFloat = 32
    }

    // MARK: - Properties

    weak var delegate: AIChatHistoryManagerDelegate?

    var isInstalled: Bool { historyManager != nil }

    private var historyManager: AIChatHistoryManager?
    private var viewModel: AIChatSuggestionsViewModel?
    private weak var floatingWrapper: UIView?
    private var heightConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()

    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let aiChatSettings: AIChatSettingsProvider
    private let iPadTabFeature: AIChatIPadTabFeatureProviding
    private let textSubject = PassthroughSubject<String, Never>()

    // MARK: - Initialization

    init(featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         aiChatSettings: AIChatSettingsProvider,
         iPadTabFeature: AIChatIPadTabFeatureProviding) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.aiChatSettings = aiChatSettings
        self.iPadTabFeature = iPadTabFeature
    }

    // MARK: - Public Methods

    /// Installs the chat history list below the given search container view.
    /// - Parameters:
    ///   - parentView: The view to add the floating panel to.
    ///   - parentViewController: The parent view controller for child VC containment.
    ///   - searchContainer: The omnibar search area view to anchor below.
    ///   - keyboardLayoutGuide: The keyboard layout guide for bottom constraint.
    func install(in parentView: UIView,
                 parentViewController: UIViewController,
                 searchContainer: UIView,
                 keyboardLayoutGuide: UILayoutGuide) {
        guard historyManager == nil else { return }
        guard iPadTabFeature.isAvailable else { return }
        guard featureFlagger.isFeatureOn(.aiChatSuggestions),
              aiChatSettings.isChatSuggestionsEnabled else { return }

        let (manager, viewModel) = makeHistoryManager()
        manager.delegate = delegate

        let (wrapper, clipView) = makeFloatingWrapper()
        wrapper.isHidden = true
        parentView.addSubview(wrapper)

        let heightConstraint = wrapper.heightAnchor.constraint(equalToConstant: 0)
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            wrapper.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: Layout.topSpacing),
            wrapper.centerXAnchor.constraint(equalTo: searchContainer.centerXAnchor),
            wrapper.widthAnchor.constraint(equalTo: searchContainer.widthAnchor),
            wrapper.bottomAnchor.constraint(lessThanOrEqualTo: keyboardLayoutGuide.topAnchor),
            heightConstraint
        ])

        manager.installInContainerView(clipView, parentViewController: parentViewController)
        manager.subscribeToTextChanges(textSubject.eraseToAnyPublisher())

        viewModel.$filteredSuggestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestions in
                guard let self else { return }
                let count = CGFloat(suggestions.count)
                let height = suggestions.isEmpty ? 0 : count * Layout.cellHeight + Layout.groupedSectionPadding
                self.heightConstraint?.constant = height
                self.floatingWrapper?.isHidden = suggestions.isEmpty
            }
            .store(in: &cancellables)

        self.floatingWrapper = wrapper
        self.historyManager = manager
        self.viewModel = viewModel
    }

    /// Tears down the chat history list and removes the floating panel.
    func tearDown() {
        cancellables.removeAll()

        historyManager?.tearDown()
        historyManager = nil
        viewModel = nil
        heightConstraint = nil

        floatingWrapper?.removeFromSuperview()
        floatingWrapper = nil
    }

    /// Forwards a text change from the AI Chat text view to filter suggestions.
    func updateQuery(_ query: String) {
        textSubject.send(query)
    }

    // MARK: - Private Methods

    private func makeHistoryManager() -> (AIChatHistoryManager, AIChatSuggestionsViewModel) {
        let reader = SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: privacyConfigurationManager)
        let historySettings = AIChatHistorySettings(privacyConfig: privacyConfigurationManager)
        let suggestionsReader = AIChatSuggestionsReader(suggestionsReader: reader, historySettings: historySettings)
        let viewModel = AIChatSuggestionsViewModel(maxSuggestions: suggestionsReader.maxHistoryCount)

        let manager = AIChatHistoryManager(suggestionsReader: suggestionsReader,
                                           aiChatSettings: aiChatSettings,
                                           viewModel: viewModel,
                                           isIPadExperience: true)
        return (manager, viewModel)
    }

    /// Returns the shadow wrapper and an inner clip view for installing content.
    private func makeFloatingWrapper() -> (CompositeShadowView, UIView) {
        let wrapper = CompositeShadowView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.backgroundColor = UIColor(designSystemColor: .background)
        wrapper.layer.cornerRadius = Layout.cornerRadius
        wrapper.layer.cornerCurve = .continuous
        wrapper.applyDefaultShadow()

        let clipView = UIView()
        clipView.translatesAutoresizingMaskIntoConstraints = false
        clipView.layer.cornerRadius = Layout.cornerRadius
        clipView.layer.cornerCurve = .continuous
        clipView.clipsToBounds = true
        wrapper.addSubview(clipView)

        NSLayoutConstraint.activate([
            clipView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            clipView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            clipView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            clipView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])

        return (wrapper, clipView)
    }
}
