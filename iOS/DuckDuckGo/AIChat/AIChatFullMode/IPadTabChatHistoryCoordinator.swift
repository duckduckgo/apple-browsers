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
import UIKit

/// Coordinates the AI chat history list displayed below the expanded omnibar in iPad tab mode.
@MainActor
final class IPadTabChatHistoryCoordinator {

    // MARK: - Constants

    private enum Layout {
        static let cornerRadius: CGFloat = 24
        static let topSpacing: CGFloat = 4
        static let widthPadding: CGFloat = 32
    }

    // MARK: - Properties

    weak var delegate: AIChatHistoryManagerDelegate?

    var isInstalled: Bool { historyManager != nil }

    private var historyManager: AIChatHistoryManager?
    private weak var floatingWrapper: UIView?

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

        let manager = makeHistoryManager()
        manager.delegate = delegate

        let wrapper = makeFloatingWrapper()
        parentView.addSubview(wrapper)

        let searchWidth = searchContainer.frame.width + Layout.widthPadding
        NSLayoutConstraint.activate([
            wrapper.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: Layout.topSpacing),
            wrapper.centerXAnchor.constraint(equalTo: searchContainer.centerXAnchor),
            wrapper.widthAnchor.constraint(equalToConstant: searchWidth),
            wrapper.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)
        ])

        manager.installInContainerView(wrapper, parentViewController: parentViewController)
        manager.subscribeToTextChanges(textSubject.eraseToAnyPublisher())

        self.floatingWrapper = wrapper
        self.historyManager = manager
    }

    /// Tears down the chat history list and removes the floating panel.
    func tearDown() {
        historyManager?.tearDown()
        historyManager = nil

        floatingWrapper?.removeFromSuperview()
        floatingWrapper = nil
    }

    /// Forwards a text change from the AI Chat text view to filter suggestions.
    func updateQuery(_ query: String) {
        textSubject.send(query)
    }

    // MARK: - Private Methods

    private func makeHistoryManager() -> AIChatHistoryManager {
        let reader = SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: privacyConfigurationManager)
        let historySettings = AIChatHistorySettings(privacyConfig: privacyConfigurationManager)
        let suggestionsReader = AIChatSuggestionsReader(suggestionsReader: reader, historySettings: historySettings)
        let viewModel = AIChatSuggestionsViewModel(maxSuggestions: suggestionsReader.maxHistoryCount)

        return AIChatHistoryManager(suggestionsReader: suggestionsReader,
                                    aiChatSettings: aiChatSettings,
                                    viewModel: viewModel)
    }

    private func makeFloatingWrapper() -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.backgroundColor = UIColor(designSystemColor: .background)
        wrapper.layer.cornerRadius = Layout.cornerRadius
        wrapper.layer.masksToBounds = true
        return wrapper
    }
}
