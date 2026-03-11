//
//  PromoService.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import os.log

final class PromoService: @unchecked Sendable, PromoHistoryProviding {

    /// Tracks state for a promo that is currently being shown.
    private struct ActiveShowSession {
        let promoId: String
        let delegate: any PromoDelegate
        let promoType: PromoType

        /// First-write-wins flag. Once true, ignore further results from show(), timeout, or eligibility.
        var isResultRecorded = false

        /// Task that awaits delegate.show() and records the result. Cancelled when session is cleaned up.
        var showTask: Task<Void, Never>?

        /// Timer that fires after promoType.timeoutInterval. On fire, records timeoutResult if !isResultRecorded.
        var timeout: TimedFlag?

        /// Subscription to isEligiblePublisher. On false, calls hide() so the promo resumes with its chosen result; the result flows through recordResultAndCleanup.
        var eligibilityCancellable: AnyCancellable?
    }

    // MARK: - Public API

    /// Currently visible promos.
    var visiblePromosPublisher: AnyPublisher<[Promo], Never> {
        visiblePromoIds
            .receive(on: stateQueue)
            .map { [weak self] ids in
                ids.compactMap { id in self?.promos.first { $0.id == id } }
            }
            .eraseToAnyPublisher()
    }

    /// Manually dismiss a promo by ID.
    func dismiss(promoId: String, result: PromoResult) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            if activeSessions[promoId] != nil {
                recordResultAndCleanup(promoId: promoId, result: result)
            } else if externalVisiblePromoIds.contains(promoId) {
                externalVisiblePromoIds.remove(promoId)
                applyResult(result, toRecordFor: promoId)
            } else {
                updateHistoryForDismissedPromo(promoId: promoId, result: result)
            }
        }
    }

    /// Reverse a dismissal.
    /// - clearHistory == false: clears LastDismissed and NextEligible; preserves TimesDismissed, Actioned, LastShown.
    /// - clearHistory == true: resets all history fields.
    func undismiss(promoId: String, clearHistory: Bool) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            var record = historyStore.record(for: promoId)
            record.nextEligibleDate = nil
            record.lastDismissed = nil
            if clearHistory {
                record.timesDismissed = 0
                record.lastShown = nil
                record.actioned = false
            }
            historyStore.save(record)
            notifyRecordChanged(for: promoId, record: record)
        }
    }

    /// Starts the service with a short delay, giving the URL event handler time to deliver its Apple Event and set the external activation flag.
    func applicationDidBecomeActive() {
        stateQueue.async { [weak self] in
            self?.deferEvaluation()
            self?.start()
        }
    }

    /// Attaches a delegate to a promo by ID. Call when the delegate object is ready.
    /// If all delegates are ready and start() was already called, completes registration immediately.
    func setDelegate(for promoId: String, delegate: any AnyPromoDelegate) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard let index = promos.firstIndex(where: { $0.id == promoId }) else {
                Logger.general.warning("PromoService: unknown promo ID \(promoId)")
                return
            }
            let previousDelegate = promos[index].delegate
            promos[index].delegate = delegate
            if let previousDelegate, (previousDelegate as AnyObject) !== (delegate as AnyObject) {
                externalSubscriptions.removeValue(forKey: promoId)?.cancel()
            }
            subscribeToExternalDelegateIfNeeded(promoId: promoId, delegate: delegate)

            if isStarted && !isDelegateRegistrationComplete && allDelegatesReady {
                completeRegistration()
            }
        }
    }

    // MARK: - Debug / Testing

    /// Debug: simulated "now" for cooldown and eligibility checks.
    /// In-memory only; nil in production.
    private var debugSimulatedDate: Date?

    private var currentDate: Date {
        debugSimulatedDate ?? Date()
    }

    /// Test-only accessor for draining the state queue. Use `drainStateQueue()` in tests.
    var testQueue: DispatchQueue { stateQueue }

    /// Debug: Set a simulated "now" for cooldown and eligibility checks. In-memory only; does not persist across app launches.
    func setDebugSimulatedDate(_ date: Date?) {
        stateQueue.async { [weak self] in
            self?.debugSimulatedDate = date
        }
    }

    /// Clears debug date override and all promo history. For debug reset.
    func resetDebugState() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            debugSimulatedDate = nil
            for (_, session) in activeSessions {
                session.showTask?.cancel()
                session.timeout?.cancel()
                session.eligibilityCancellable?.cancel()
                let delegate = session.delegate
                Task { @MainActor in
                    delegate.hide()
                }
            }
            activeSessions.removeAll()
            historyStore.resetAll()
            recordsSubject.send([:])

            for promo in promos {
                guard let delegate = promo.delegate as? TestPromoDelegate else { continue }
                delegate.resetEligibility()
            }
        }
    }

    /// Debug: Force-show a promo by ID, bypassing all evaluation rules. Does not affect history or cooldowns.
    /// No-op for external promos (ExternalPromoDelegate); they control their own visibility.
    func forceShow(promoId: String) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard let promo = promos.first(where: { $0.id == promoId }) else {
                Logger.general.warning("PromoService: forceShow unknown promo ID \(promoId)")
                return
            }
            guard let delegate = promo.delegate as? PromoDelegate else {
                Logger.general.warning("PromoService: forceShow - external promos control their own visibility")
                return
            }
            let record = historyStore.record(for: promoId)
            Task { @MainActor in
                _ = await delegate.show(history: record)
                delegate.hide()
            }
        }
    }

    // MARK: - Internal State

    // MARK: Delegate registration

    /// After delegate registration completes, evaluation begins.
    private var isDelegateRegistrationComplete = false

    /// Provides a fallback to proceed with `completeRegistration()` when delegates are not all ready.
    /// Cancelled if delegates are all set within the timeout.
    private let registrationTimeout: TimedFlag

    /// True when every promo in promos has a non-nil delegate.
    private var allDelegatesReady: Bool {
        promos.allSatisfy { $0.delegate != nil }
    }

    // MARK: External URL app activation handling

    /// Defers trigger evaluation when set, giving the URL event handler time to deliver its Apple Event and set the external activation flag.
    private let triggerEvaluationDeferral: TimedFlag

    /// Suppresses all promos when set, preventing promo shows while the user is likely focused on content related to the external activation (e.g. opening a link).
    private let externalActivationSuppression: TimedFlag

    // MARK: Promos

    /// Fixed list of promos (array order = priority order). Delegates attached via setDelegate(for:delegate:).
    private(set) var promos: [Promo]

    /// Whether `PromoService` has started evaluating promo triggers and showing eligible promos.
    private var isStarted = false

    /// Promo history storage.
    private let historyStore: PromoHistoryStoring

    /// Publisher for promo triggers.
    private let triggerPublisher: AnyPublisher<PromoTrigger, Never>

    /// Triggers to be evaluated after delegate registration and deferral window ends.
    private var bufferedTriggers = Set<PromoTrigger>()

    /// Currently visible promos by ID, and their active show sessions
    private var activeSessions: [String: ActiveShowSession] = [:] {
        didSet {
            if activeSessions.keys != oldValue.keys {
                publishVisiblePromoIds()
            }
        }
    }

    /// External promos that are visible (driven by their delegates' isVisiblePublisher). Union with activeSessions for rules and visibility.
    private var externalVisiblePromoIds: Set<String> = [] {
        didSet {
            if externalVisiblePromoIds != oldValue {
                publishVisiblePromoIds()
            }
        }
    }

    /// Subscriptions to external delegates' isVisiblePublisher. Keyed by promoId.
    private var externalSubscriptions: [String: AnyCancellable] = [:]

    /// Currently visible promos by ID. Kept in sync with `activeSessions`, `externalVisiblePromoIds`, and persisted to `historyStore` on change.
    private let visiblePromoIds: CurrentValueSubject<Set<String>, Never>

    /// Snapshot of promo history records for PromoHistoryProviding. Updated on save/reset.
    private let recordsSubject: CurrentValueSubject<[String: PromoHistoryRecord], Never>

    private var cancellables = Set<AnyCancellable>()

    /// Serial queue that protects all mutable state and runs trigger evaluation off the main thread.
    private let stateQueue: DispatchQueue

    // MARK: - Init

    init(
        promos: [Promo],
        historyStore: PromoHistoryStoring,
        triggerPublisher: AnyPublisher<PromoTrigger, Never>,
        initialExternalActivation: Bool = false,
        stateQueue: DispatchQueue = DispatchQueue(label: "com.duckduckgo.promoService.state"),
        evaluationDeferralWindow: TimeInterval = 0.5,
        registrationFallbackTimeout: TimeInterval = 1.0,
        externalActivationWindow: TimeInterval = 5.0
    ) {
        self.promos = promos
        self.historyStore = historyStore
        self.triggerPublisher = triggerPublisher
        self.stateQueue = stateQueue
        self.registrationTimeout = TimedFlag(queue: stateQueue, clearAfter: registrationFallbackTimeout)
        self.triggerEvaluationDeferral = TimedFlag(queue: stateQueue, clearAfter: evaluationDeferralWindow)
        self.externalActivationSuppression = TimedFlag(queue: stateQueue, clearAfter: externalActivationWindow)
        self.visiblePromoIds = CurrentValueSubject([])
        var initialSnapshot: [String: PromoHistoryRecord] = [:]
        stateQueue.sync {
            for promo in promos {
                initialSnapshot[promo.id] = historyStore.record(for: promo.id)
            }
        }
        self.recordsSubject = CurrentValueSubject(initialSnapshot)

        triggerPublisher
            .receive(on: stateQueue)
            .sink { [weak self] trigger in
                guard let self else { return }
                if !isDelegateRegistrationComplete || triggerEvaluationDeferral.isSet {
                    bufferedTriggers.insert(trigger)
                } else {
                    evaluateTriggers([trigger])
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .externalURLHandled)
            .receive(on: stateQueue)
            .sink { [weak self] _ in
                self?.suppressPromosAfterExternalActivation()
            }
            .store(in: &cancellables)

        if initialExternalActivation {
            stateQueue.async { [weak self] in
                self?.suppressPromosAfterExternalActivation()
            }
        }
    }

    // MARK: - Lifecycle

    deinit {
        registrationTimeout.cancel()
        triggerEvaluationDeferral.cancel()
        externalActivationSuppression.cancel()
    }

    /// Suppresses promos for a short window when the app was activated by an external source (e.g. deep link).
    private func suppressPromosAfterExternalActivation() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        externalActivationSuppression.set()
    }

    /// Defers trigger evaluation for a short window after app activation, giving the URL event handler time to deliver its Apple Event and set the external activation flag.
    private func deferEvaluation() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        triggerEvaluationDeferral.set { [weak self] in
            self?.processBufferedTriggersIfReady()
        }
    }

    /// Begins evaluation. If all delegates are ready, evaluation starts immediately.
    /// Otherwise, starts a fallback timeout (1s) after which evaluation begins with available delegates.
    private func start() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard !isStarted else { return }
        isStarted = true

        if allDelegatesReady {
            completeRegistration()
            return
        }

        registrationTimeout.set { [weak self] in
            self?.completeRegistration()
        }
    }

    private func completeRegistration() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard !isDelegateRegistrationComplete else { return }
        isDelegateRegistrationComplete = true
        registrationTimeout.cancel()

        for promo in promos {
            subscribeToExternalDelegateIfNeeded(promoId: promo.id, delegate: promo.delegate)
        }

        restoreVisiblePromos()
        processBufferedTriggersIfReady()
    }

    private func subscribeToExternalDelegateIfNeeded(promoId: String, delegate: (any AnyPromoDelegate)?) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard let externalDelegate = delegate as? ExternalPromoDelegate else { return }
        guard externalSubscriptions[promoId] == nil else { return }

        applyExternalVisibility(visible: externalDelegate.isVisible, promoId: promoId, delegate: externalDelegate)

        let cancellable = externalDelegate.isVisiblePublisher
            .dropFirst()
            .receive(on: stateQueue)
            .sink { [weak self] visible in
                guard let self else { return }
                applyExternalVisibility(visible: visible, promoId: promoId, delegate: externalDelegate)
            }
        externalSubscriptions[promoId] = cancellable
    }

    private func applyExternalVisibility(visible: Bool, promoId: String, delegate: ExternalPromoDelegate) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        if visible {
            externalVisiblePromoIds.insert(promoId)
            var record = historyStore.record(for: promoId)
            record.lastShown = currentDate
            historyStore.save(record)
            notifyRecordChanged(for: promoId, record: record)
        } else if externalVisiblePromoIds.remove(promoId) != nil {
            applyResult(delegate.resultWhenHidden, toRecordFor: promoId)
        }
    }

    /// Processes buffered triggers after all delegates are registered, if the deferral window has ended,
    /// and if not currently suppressing promos for external activation.
    /// Buffered triggers are intentionally discarded if the app was externally activated.
    private func processBufferedTriggersIfReady() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard isDelegateRegistrationComplete, !triggerEvaluationDeferral.isSet else { return }

        let buffered = bufferedTriggers
        bufferedTriggers.removeAll()
        guard !buffered.isEmpty, !externalActivationSuppression.isSet else { return }

        evaluateTriggers(buffered)
    }

    // MARK: - Trigger Evaluation

    private func restoreVisiblePromos() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard !externalActivationSuppression.isSet else { return }

        for promo in promos {
            guard let delegate = promo.delegate as? PromoDelegate else { continue }
            let record = historyStore.record(for: promo.id)

            guard let lastShown = record.lastShown else { continue }
            let wasVisibleAtShutdown = record.lastDismissed == nil
                || record.lastDismissed! < lastShown
            guard wasVisibleAtShutdown else { continue }

            delegate.refreshEligibility()
            guard delegate.isEligible else { continue }

            performShow(promo: promo, delegate: delegate, record: record, isRestore: true)
        }
    }

    /// Evaluates triggers by finding promos matching the providing trigger(s), refreshing their eligibility,
    /// and showing any that are newly eligible. Triggers are evaluated in promo priority order.
    private func evaluateTriggers(_ triggers: Set<PromoTrigger>) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        let matchingPromos = promos.filter { $0.triggers.contains(where: triggers.contains) }
        for promo in matchingPromos {
            (promo.delegate as? PromoDelegate)?.refreshEligibility()
        }

        for promo in matchingPromos {
            guard activeSessions[promo.id] == nil,
                  let delegate = promo.delegate as? PromoDelegate,
                  checkRules(for: promo) else { continue }

            let record = historyStore.record(for: promo.id)
            guard !record.isPermanentlyDismissed, record.isEligible(asOf: currentDate) else { continue }
            guard delegate.isEligible else { continue }

            performShow(promo: promo, delegate: delegate, record: record, isRestore: false)
        }
    }

    private func publishVisiblePromoIds() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        visiblePromoIds.send(Set(activeSessions.keys).union(externalVisiblePromoIds))
    }

    private func checkRules(for promo: Promo) -> Bool {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        if promo.promoType.severity == .low { return true }
        if externalActivationSuppression.isSet { return false }

        let visibleIds = Set(activeSessions.keys).union(externalVisiblePromoIds)
        let promoId = promo.id
        let severity = promo.promoType.severity
        let context = promo.context
        let coexisting = promo.coexistingPromoIDs

        for otherId in visibleIds where otherId != promoId {
            guard let other = promos.first(where: { $0.id == otherId }) else { continue }
            let mutuallyCoexisting = coexisting.contains(otherId) && other.coexistingPromoIDs.contains(promoId)

            let contextConflict = !mutuallyCoexisting && (
                context == .global || other.context == .global || context == other.context
            )
            if contextConflict { return false }

            if severity >= .medium && other.promoType.severity >= .medium && !mutuallyCoexisting {
                return false
            }
        }

        if promo.respectsGlobalCooldown && severity >= .medium {
            let lastDismissedForType = promos
                .filter { $0.initiated == promo.initiated && $0.setsGlobalCooldown && $0.promoType.severity >= .medium }
                .compactMap { historyStore.record(for: $0.id).lastDismissed }
                .max()
            if let last = lastDismissedForType, currentDate.timeIntervalSince(last) < promo.initiated.cooldown {
                return false
            }
        }

        return true
    }

    // MARK: - Show / Session Management

    private func performShow(promo: Promo, delegate: PromoDelegate, record: PromoHistoryRecord, isRestore: Bool = false) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        let promoId = promo.id
        var recordToUse = record
        if !isRestore {
            recordToUse.lastShown = currentDate
        }
        historyStore.save(recordToUse)
        notifyRecordChanged(for: promoId, record: recordToUse)

        let eligibilityCancellable = delegate.isEligiblePublisher
            .dropFirst()
            .receive(on: stateQueue)
            .sink { [weak self] eligible in
                guard !eligible else { return }
                self?.handleEligibilityLost(promoId: promoId)
            }

        var timeout: TimedFlag?
        if let interval = promo.promoType.timeoutInterval {
            let flag = TimedFlag(queue: stateQueue, clearAfter: interval)
            flag.set { [weak self] in
                self?.handleTimeout(promoId: promoId)
            }
            timeout = flag
        }

        let showTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let result = await delegate.show(history: recordToUse)
            self?.stateQueue.async { [weak self] in
                self?.recordResultAndCleanup(promoId: promoId, result: result)
            }
        }

        let session = ActiveShowSession(
            promoId: promoId,
            delegate: delegate,
            promoType: promo.promoType,
            isResultRecorded: false,
            showTask: showTask,
            timeout: timeout,
            eligibilityCancellable: eligibilityCancellable
        )
        activeSessions[promoId] = session
    }

    // MARK: - Result Handling

    private func handleTimeout(promoId: String) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard let session = activeSessions[promoId] else { return }
        recordResultAndCleanup(promoId: promoId, result: session.promoType.timeoutResult)
    }

    private func handleEligibilityLost(promoId: String) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        recordResultAndCleanup(promoId: promoId, result: .noChange)
    }

    private func recordResultAndCleanup(promoId: String, result: PromoResult) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard var session = activeSessions[promoId] else { return }
        if session.isResultRecorded { return }

        session.isResultRecorded = true
        activeSessions[promoId] = session

        session.showTask?.cancel()
        session.showTask = nil
        session.timeout?.cancel()
        session.timeout = nil
        session.eligibilityCancellable?.cancel()
        session.eligibilityCancellable = nil

        applyResult(result, toRecordFor: promoId)

        activeSessions.removeValue(forKey: promoId)

        let delegate = session.delegate
        Task { @MainActor in
            delegate.hide()
        }
    }

    private func updateHistoryForDismissedPromo(promoId: String, result: PromoResult) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        applyResult(result, toRecordFor: promoId)
    }

    private func applyResult(_ result: PromoResult, toRecordFor promoId: String) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        var record = historyStore.record(for: promoId)
        switch result {
        case .actioned:
            record.timesDismissed += 1
            record.lastDismissed = currentDate
            record.nextEligibleDate = .distantFuture
            record.actioned = true
        case .ignored(cooldown: nil):
            record.timesDismissed += 1
            record.lastDismissed = currentDate
            record.nextEligibleDate = .distantFuture
        case .ignored(cooldown: let interval?):
            record.timesDismissed += 1
            record.lastDismissed = currentDate
            record.nextEligibleDate = currentDate.addingTimeInterval(interval)
        case .noChange:
            record.lastShown = nil // Ensure promo is not restored if it was retracted before app restart
        }
        historyStore.save(record)
        notifyRecordChanged(for: promoId, record: record)
    }

    private func notifyRecordChanged(for promoId: String, record: PromoHistoryRecord) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        var snapshot = recordsSubject.value
        snapshot[promoId] = record
        recordsSubject.send(snapshot)
    }

    // MARK: - PromoHistoryProviding

    func historyPublisher(for promoId: String) -> AnyPublisher<PromoHistoryRecord?, Never> {
        recordsSubject
            .map { $0[promoId] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var allHistoryPublisher: AnyPublisher<[PromoHistoryRecord], Never> {
        recordsSubject
            .map { Array($0.values) }
            .eraseToAnyPublisher()
    }
}
