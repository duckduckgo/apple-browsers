//
//  NewTabPageOmnibarConfigProvider.swift
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
import AppKit
import WebKit
import Combine
import FeatureFlags_macOS
import NewTabPage
import PrivacyConfig
import os.log
import Persistence
import PixelKit
import Common
import FoundationExtensions

protocol NewTabPageAIChatShortcutSettingProviding: AnyObject {
    var isAIChatShortcutEnabled: Bool { get set }
    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> { get }
    var isAIChatSettingVisible: Bool { get }
    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> { get }
}

final class NewTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding {
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private var aiChatPreferencesStorage: AIChatPreferencesStorage

    init(
        aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
        aiChatPreferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage()
    ) {
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.aiChatPreferencesStorage = aiChatPreferencesStorage
    }

    var isAIChatShortcutEnabled: Bool {
        get {
            aiChatMenuConfiguration.shouldDisplayNewTabPageShortcut
        }
        set {
            aiChatPreferencesStorage.showShortcutOnNewTabPage = newValue
        }
    }

    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> {
        aiChatMenuConfiguration.valuesChangedPublisher
            .compactMap { [weak self] in
                self?.aiChatMenuConfiguration
            }
            .map(\.shouldDisplayNewTabPageShortcut)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var isAIChatSettingVisible: Bool {
        aiChatPreferencesStorage.isAIFeaturesEnabled
    }

    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> {
        aiChatPreferencesStorage.isAIFeaturesEnabledPublisher.eraseToAnyPublisher()
    }
}

final class NewTabPageOmnibarConfigProvider: NewTabPageOmnibarConfigProviding {
    private enum Key: String {
        case newTabPageOmnibarMode
    }

    private enum LegacyKey: String {
        /// Previously-used per-NTP key. Migrated into `AIChatPreferencesPersisting.selectedModelId`
        /// (shared with the native omnibar) on first init after the unification, then removed.
        case newTabPageSelectedModelId
    }

    private enum Constants: Int {
        case maxNumberOfPopoverPresentations = 5
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let aiChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding
    private let featureFlagger: FeatureFlagger
    private let firePixel: (PixelKit.Event) -> Void
    private var aiChatPreferencesPersistor: AIChatPreferencesPersisting
    private let searchPreferences: SearchPreferences
    private let windowControllersManager: WindowControllersManagerProtocol?
    private let duckAiStorageHandlerProvider: (BurnerMode) -> DuckAiNativeStorageHandling?
    private let userTierProvider: () -> AIChatUserTier
    private let availableModelsProvider: () -> [AIChatModel]
    private let isTrialEligibleProvider: () -> Bool
    private let showCustomizePopoverSubject = PassthroughSubject<Bool, Never>()
    private let modeSubject = PassthroughSubject<NewTabPageDataModel.OmnibarMode, Never>()
    private let customizeResponsesChangedSubject = PassthroughSubject<Void, Never>()
    private let usageLimitsChangedSubject = PassthroughSubject<Void, Never>()
    @Published private var hasExcessChats = false
    private var aiChatsProviderCancellable: AnyCancellable?
    private var customizeResponsesChangeObserver: NSObjectProtocol?

    init(keyValueStore: ThrowingKeyValueStoring,
         aiChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding,
         featureFlagger: FeatureFlagger,
         aiChatPreferencesPersistor: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
         searchPreferences: SearchPreferences,
         windowControllersManager: WindowControllersManagerProtocol? = nil,
         duckAiStorageHandlerProvider: @escaping (BurnerMode) -> DuckAiNativeStorageHandling? = { _ in nil },
         userTierProvider: @escaping () -> AIChatUserTier = { .free },
         availableModelsProvider: @escaping () -> [AIChatModel] = { [] },
         isTrialEligibleProvider: @escaping () -> Bool = { false },
         firePixel: @escaping (PixelKit.Event) -> Void = { PixelKit.fire($0, frequency: .dailyAndStandard) }) {
        self.keyValueStore = keyValueStore
        self.aiChatShortcutSettingProvider = aiChatShortcutSettingProvider
        self.featureFlagger = featureFlagger
        self.aiChatPreferencesPersistor = aiChatPreferencesPersistor
        self.searchPreferences = searchPreferences
        self.windowControllersManager = windowControllersManager
        self.duckAiStorageHandlerProvider = duckAiStorageHandlerProvider
        self.userTierProvider = userTierProvider
        self.availableModelsProvider = availableModelsProvider
        self.isTrialEligibleProvider = isTrialEligibleProvider
        self.firePixel = firePixel

        Self.migrateLegacySelectedModelIdIfNeeded(from: keyValueStore, into: &self.aiChatPreferencesPersistor)

        // Address-bar Customize Responses changes (modal or toggle) post this; re-push config so open
        // NTPs update without waiting for their own toggle. The NTP's own paths notify directly.
        customizeResponsesChangeObserver = NotificationCenter.default.addObserver(
            forName: .aiChatCustomizeResponsesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notifyCustomizeResponsesChanged()
        }
    }

    deinit {
        if let customizeResponsesChangeObserver {
            NotificationCenter.default.removeObserver(customizeResponsesChangeObserver)
        }
    }

    @MainActor
    var mode: NewTabPageDataModel.OmnibarMode {
        get {
            guard isAIChatShortcutEnabled && isAIChatSettingVisible else {
                return .search
            }
            do {
                if let rawValue = try keyValueStore.object(forKey: Key.newTabPageOmnibarMode.rawValue) as? String,
                   let mode = NewTabPageDataModel.OmnibarMode(rawValue: rawValue) {
                    return mode
                }
            } catch {
                Logger.newTabPageOmnibar.error("Failed to retrieve omnibar mode from keyValueStore: \(error.localizedDescription)")
            }
            return .search
        }
        set {
            firePixel(NewTabPagePixel.omnibarModeChanged(mode: newValue == .search ? .search : .duckAI))
            do {
                try keyValueStore.set(newValue.rawValue, forKey: Key.newTabPageOmnibarMode.rawValue)
            } catch {
                Logger.newTabPageOmnibar.error("Failed to set omnibar mode in keyValueStore: \(error.localizedDescription)")
            }
            modeSubject.send(newValue)
        }
    }

    var isAIChatShortcutEnabled: Bool {
        get {
            aiChatShortcutSettingProvider.isAIChatShortcutEnabled
        }
        set {
            aiChatShortcutSettingProvider.isAIChatShortcutEnabled = newValue
        }
    }

    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> {
        aiChatShortcutSettingProvider.isAIChatShortcutEnabledPublisher
    }

    var isAIChatSettingVisible: Bool {
        aiChatShortcutSettingProvider.isAIChatSettingVisible
    }

    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> {
        aiChatShortcutSettingProvider.isAIChatSettingVisiblePublisher
    }

    var modePublisher: AnyPublisher<NewTabPageDataModel.OmnibarMode, Never> {
        modeSubject.eraseToAnyPublisher()
    }

    var isAIChatRecentChatsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpRecentChats)
    }

    var isAIChatToolsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpChatTools)
    }

    var selectedModelId: String? {
        get {
            aiChatPreferencesPersistor.selectedModelId
        }
        set {
            guard newValue != aiChatPreferencesPersistor.selectedModelId else { return }
            // The drawer's CTA by another route, so it settles the message too. Before the write:
            // it needs the model we were on.
            if let newValue {
                usageWarningViewModel?.userSwitchedModel(from: aiChatPreferencesPersistor.selectedModelId, to: newValue)
            }
            aiChatPreferencesPersistor.selectedModelId = newValue
            if newValue != nil {
                PixelKit.fire(AIChatPixel.aiChatNtpModelSelected, frequency: .dailyAndCount, includeAppVersionParameter: true)
            }
        }
    }

    var selectedModelIdPublisher: AnyPublisher<String?, Never> {
        aiChatPreferencesPersistor.selectedModelIdPublisher
    }

    var selectedModelShortName: String? {
        get {
            aiChatPreferencesPersistor.selectedModelShortName
        }
        set {
            aiChatPreferencesPersistor.selectedModelShortName = newValue
        }
    }

    var isReasoningEffortEnabled: Bool {
        // Reasoning effort depends on the model picker being available — if tools aren't
        // enabled, there's no model picker and reasoning has nothing to attach to.
        isAIChatToolsEnabled && featureFlagger.isFeatureOn(.aiChatOmnibarReasoningEffort)
    }

    var selectedReasoningEffort: String? {
        get {
            guard isReasoningEffortEnabled else { return nil }
            return aiChatPreferencesPersistor.selectedReasoningEffort
        }
        set {
            guard isReasoningEffortEnabled else { return }
            guard newValue != aiChatPreferencesPersistor.selectedReasoningEffort else { return }
            aiChatPreferencesPersistor.selectedReasoningEffort = newValue
            if newValue != nil {
                PixelKit.fire(AIChatPixel.aiChatNtpReasoningEffortSelected, frequency: .dailyAndCount, includeAppVersionParameter: true)
            }
        }
    }

    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> {
        aiChatPreferencesPersistor.selectedReasoningEffortPublisher
    }

    var isImageGenerationEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpImageGeneration)
    }

    var isUpdatedCreateImageEnabled: Bool {
        isImageGenerationEnabled && featureFlagger.isFeatureOn(.updatedCreateImage)
    }

    @MainActor
    var imageGenerationModelId: String? {
        guard isUpdatedCreateImageEnabled else { return nil }
        return imageGenerationModel(in: availableModelsProvider())?.id
    }

    @MainActor
    func activateImageGeneration() -> NewTabPageDataModel.OmnibarCreateImageModelSwitch? {
        guard isUpdatedCreateImageEnabled else { return nil }

        let models = availableModelsProvider()
        let previousModel = models.first(where: { $0.id == aiChatPreferencesPersistor.selectedModelId })
        guard let imageModel = imageGenerationModel(in: models),
              previousModel?.id != imageModel.id else {
            return nil
        }

        aiChatPreferencesPersistor.selectedModelId = imageModel.id
        aiChatPreferencesPersistor.selectedModelShortName = imageModel.shortName
        clearReasoningEffortIfUnsupported(by: imageModel)

        guard let previousModel else { return nil }
        let notice = AIChatCreateImageModelSwitchNotice(previousModel: previousModel, newModel: imageModel)
        return NewTabPageDataModel.OmnibarCreateImageModelSwitch(
            message: notice.localizedTitle,
            secondaryText: notice.localizedSubtitle
        )
    }

    private func imageGenerationModel(in models: [AIChatModel]) -> AIChatModel? {
        if let selectedModel = models.first(where: { $0.id == aiChatPreferencesPersistor.selectedModelId }),
           selectedModel.entityHasAccess,
           selectedModel.supportsTool(.imageGeneration) {
            return selectedModel
        }
        return AIChatModel.preferredImageGenerationModel(in: models)
    }

    private func clearReasoningEffortIfUnsupported(by model: AIChatModel) {
        guard let rawValue = aiChatPreferencesPersistor.selectedReasoningEffort else { return }
        guard let effort = AIChatReasoningEffort(rawValue: rawValue) else {
            aiChatPreferencesPersistor.selectedReasoningEffort = nil
            return
        }
        guard !model.supportedReasoningEffort.contains(effort) else { return }
        aiChatPreferencesPersistor.selectedReasoningEffort = nil
    }

    var isWebSearchEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpWebSearch)
    }

    var isCustomizeResponsesEnabled: Bool {
        // Gated by the dedicated Customize Responses flag, matching the native omnibar entry point.
        featureFlagger.isFeatureOn(.aiChatCustomizeResponses)
    }

    @MainActor
    func customizeResponsesState(requestingWebView: WKWebView?) -> NewTabPageDataModel.OmnibarCustomizeResponsesState {
        guard let windowControllersManager else { return .none }
        let burnerMode = AIChatTabPickerSource.originTabCollectionViewModel(for: requestingWebView, in: windowControllersManager)?.burnerMode ?? .regular
        let state = CustomizeResponsesStore(storageHandler: duckAiStorageHandlerProvider(burnerMode)).currentState()
        return NewTabPageDataModel.OmnibarCustomizeResponsesState(subLabel: state.subLabel, hasCustomization: state.hasCustomization, active: state.isActive)
    }

    var customizeResponsesStatePublisher: AnyPublisher<Void, Never> {
        customizeResponsesChangedSubject.eraseToAnyPublisher()
    }

    /// Rebuilt per refresh because the burner mode depends on the requesting webview.
    private(set) var usageWarningViewModel: DuckAiUsageWarningViewModel?
    private var highUsageNoticeSource: AIChatHighUsageNoticeSource?
    private var usageLimitsCancellables = Set<AnyCancellable>()

    var usageLimitsPublisher: AnyPublisher<Void, Never> {
        usageLimitsChangedSubject.eraseToAnyPublisher()
    }

    @MainActor
    func refreshUsageLimits(requestingWebView: WKWebView?) {
        guard let windowControllersManager else { return }
        let burnerMode = AIChatTabPickerSource.originTabCollectionViewModel(for: requestingWebView, in: windowControllersManager)?.burnerMode ?? .regular
        let store = DuckAiUsageLimitsStore(storageHandler: duckAiStorageHandlerProvider(burnerMode),
                                           featureFlagger: featureFlagger)
        usageLimitsCancellables.removeAll()
        usageWarningViewModel = store.makeWarningViewModel(
            modelSuggester: DuckAiModelSuggester(
                modelsProvider: availableModelsProvider,
                currentModelIdProvider: { [aiChatPreferencesPersistor] in aiChatPreferencesPersistor.selectedModelId }
            ),
            isTrialEligible: isTrialEligibleProvider,
            isFireMode: { burnerMode.isBurner }
        )
        highUsageNoticeSource = store.makeHighUsageNoticeSource(modelProvider: { [aiChatPreferencesPersistor] in
            (aiChatPreferencesPersistor.selectedModelId, aiChatPreferencesPersistor.selectedModelShortName)
        })
        usageWarningViewModel?.onAction = { [weak self, store] action in
            switch action {
            case .switchToModel(let suggestion), .switchToFreeModel(let suggestion):
                self?.applyModelSwitch(toModelId: suggestion.modelId, shortName: suggestion.modelShortName)
            case .startUsingWeeklyLimit(let entries):
                // The captured store carries this refresh's burner-aware handler.
                store.write(entries)
            case .tryForFree:
                // The client raises this off `selectUsageLimitsCta`'s outcome instead.
                break
            }
        }
        usageWarningViewModel?.refresh()

        store.snapshotUpdates?
            .sink { [weak self] in self?.usageWarningViewModel?.refresh() }
            .store(in: &usageLimitsCancellables)
        // After the first resolve, so entering Duck.ai mode doesn't push an update on top of the
        // `getConfig` response that triggered it.
        usageWarningViewModel?.$warning
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.usageLimitsChangedSubject.send(()) }
            .store(in: &usageLimitsCancellables)
    }

    @MainActor
    func usageLimits() -> NewTabPageDataModel.OmnibarUsageLimits? {
        if let warning = usageWarningViewModel?.warning {
            return NewTabPageDataModel.OmnibarUsageLimits(warning: warning,
                                                          alternatives: modelPickerAlternatives(for: warning))
        }
        highUsageNoticeSource?.refresh()
        guard let notice = highUsageNoticeSource?.notice else { return nil }
        return NewTabPageDataModel.OmnibarUsageLimits(notice: notice)
    }

    @MainActor
    func dismissUsageLimits() {
        if usageWarningViewModel?.warning != nil {
            usageWarningViewModel?.dismiss()
            return
        }
        // Re-resolved first: dismissing a notice that hasn't been read since the model changed
        // records nothing and lets it come back.
        highUsageNoticeSource?.refresh()
        highUsageNoticeSource?.dismissCurrent()
    }

    @MainActor
    func selectUsageLimitsCta(modelId: String?) -> NewTabPageDataModel.OmnibarUsageLimitsCtaOutcome {
        guard let viewModel = usageWarningViewModel, let action = viewModel.warning?.action else { return .handled }

        guard let modelId, modelId != action.suggestedModelId else {
            viewModel.performAction()
            if case .tryForFree = action { return .requiresSubscriptionUpsell }
            return .handled
        }

        // The chevron menu is the message's own affordance, so any pick from it settles it.
        guard let model = availableModelsProvider().first(where: { $0.id == modelId && $0.entityHasAccess }) else {
            return .handled
        }
        applyModelSwitch(toModelId: model.id, shortName: model.shortName)
        viewModel.modelSwitchedFromMessage()
        return .handled
    }

    /// Mirrors `modelPickerItems` rather than offering the step-down models web named, because web
    /// can't see this surface's picker. Gated rows and the selection go because web can't render them.
    private func modelPickerAlternatives(for warning: DuckAiUsageWarning) -> [AIChatModel] {
        guard warning.actionSwapsModel else { return [] }

        let models = warning.modelPickerOffersFreeModelsOnly
            ? availableModelsProvider().filter { !$0.isAdvanced }
            : availableModelsProvider()
        let accessible = AIChatModelSectionBuilder.groupByAccess(models: models).accessible
            .filter { $0.id != aiChatPreferencesPersistor.selectedModelId }
        let byLabel = AIChatModelSectionBuilder.groupByRecommendationLabel(models: accessible)
        return byLabel.withLabel + byLabel.withoutLabel
    }

    private func applyModelSwitch(toModelId modelId: String, shortName: String?) {
        // Both, or the picker label keeps showing the model we just switched away from.
        aiChatPreferencesPersistor.selectedModelId = modelId
        aiChatPreferencesPersistor.selectedModelShortName = shortName
        guard let model = availableModelsProvider().first(where: { $0.id == modelId }) else { return }
        clearReasoningEffortIfUnsupported(by: model)
    }

    func notifyCustomizeResponsesChanged() {
        customizeResponsesChangedSubject.send(())
    }

    var isAttachTabsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpAttachMoreTabs)
    }

    /// Re-emits the current `isAttachTabsEnabled` value whenever the feature-flagger reports any
    /// change. The client uses this to push `omnibar_onConfigUpdate` so an open NTP shows or hides
    /// the attach-tabs affordance without a reload when the flag flips.
    var isAttachTabsEnabledPublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .compactMap { [weak self] in self?.isAttachTabsEnabled }
            .prepend(isAttachTabsEnabled)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var isVoiceChatAccessEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarVoiceChatAccess)
    }

    /// Re-emits the current `isVoiceChatAccessEnabled` value whenever the feature-flagger reports
    /// any change. The client uses this to push `omnibar_onConfigUpdate` so an open NTP swaps in
    /// or out of voice-chat mode without a reload.
    var isVoiceChatAccessEnabledPublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .compactMap { [weak self] in self?.isVoiceChatAccessEnabled }
            .prepend(isVoiceChatAccessEnabled)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var showAskAiSuggestion: Bool {
        searchPreferences.showAutocompleteSuggestions
    }

    /// Drops the initial value so subscriber attachment during init doesn't push a redundant
    /// `omnibar_onConfigUpdate` — matches the other `*Publisher` shapes in this provider.
    var showAskAiSuggestionPublisher: AnyPublisher<Bool, Never> {
        searchPreferences.$showAutocompleteSuggestions
            .dropFirst()
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var isAIChatDeletionEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpSuggestionsDeletion)
    }

    /// Re-emits on feature-flag change so the client can push `omnibar_onConfigUpdate` (no reload needed).
    var isAIChatDeletionEnabledPublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .compactMap { [weak self] in self?.isAIChatDeletionEnabled }
            .prepend(isAIChatDeletionEnabled)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var isSearchSuggestionDeletionEnabled: Bool {
        featureFlagger.isFeatureOn(.ntpSearchSuggestionsDeletion)
    }

    /// Re-emits on feature-flag change so the client can push `omnibar_onConfigUpdate` (no reload needed).
    var isSearchSuggestionDeletionEnabledPublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .compactMap { [weak self] in self?.isSearchSuggestionDeletionEnabled }
            .prepend(isSearchSuggestionDeletionEnabled)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var showCustomizePopover: Bool {
        get {
            // We no longer present the tooltip
            return false
        }
        set {
        }
    }

    var showViewAllAiChats: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpRecentChats)
            && featureFlagger.isFeatureOn(.aiChatNtpViewAllChats)
            && searchPreferences.showAutocompleteSuggestions
            && hasExcessChats
    }

    /// Re-evaluates `showViewAllAiChats` whenever either `hasExcessChats` or the autocomplete
    /// preference flips. Without the second input, disabling Autocomplete suggestions would leave
    /// a stale `true` in `hasExcessChats` (set on a prior `aiChats(query:)` call that fetched
    /// suggestions), and the web could be told to show a "View All" button while the chats
    /// response is empty.
    ///
    /// The closure reads the values straight off `CombineLatest` rather than calling
    /// `self.showViewAllAiChats`. `@Published` fires in `willSet`, so the stored property is
    /// still the old value when the publisher emits — reading the getter at that point would
    /// race against the assignment.
    var showViewAllAiChatsPublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest(
            $hasExcessChats,
            searchPreferences.$showAutocompleteSuggestions
        )
        .map { [weak self] hasExcess, showAutocomplete in
            guard let self else { return false }
            return self.featureFlagger.isFeatureOn(.aiChatNtpRecentChats)
                && self.featureFlagger.isFeatureOn(.aiChatNtpViewAllChats)
                && showAutocomplete
                && hasExcess
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    func configure(aiChatsProvider: NewTabPageOmnibarAiChatsProviding) {
        aiChatsProviderCancellable = aiChatsProvider.hasExcessChatsPublisher
            .sink { [weak self] hasExcess in
                guard let self else { return }
                self.hasExcessChats = hasExcess
            }
    }

    /// One-time migration: copy the old NTP-only model id into the shared `AIChatPreferencesPersisting`
    /// store when the shared value is absent, then drop the legacy key so subsequent launches skip the work.
    ///
    /// The legacy NTP store never cached a short name, so on the upgrade path we seed it with the
    /// model id as a placeholder. This keeps the native omnibar's model picker visible on first
    /// launch post-upgrade (the picker is hidden when both `models` and `selectedModelShortName`
    /// are empty). The real short name replaces the placeholder once the models fetch completes.
    private static func migrateLegacySelectedModelIdIfNeeded(
        from keyValueStore: ThrowingKeyValueStoring,
        into persistor: inout AIChatPreferencesPersisting
    ) {
        let legacyKey = LegacyKey.newTabPageSelectedModelId.rawValue
        guard let legacyValue = try? keyValueStore.object(forKey: legacyKey) as? String else {
            return
        }
        if persistor.selectedModelId == nil {
            persistor.selectedModelId = legacyValue
            if persistor.selectedModelShortName == nil {
                persistor.selectedModelShortName = legacyValue
            }
        }
        try? keyValueStore.removeObject(forKey: legacyKey)
    }

}
