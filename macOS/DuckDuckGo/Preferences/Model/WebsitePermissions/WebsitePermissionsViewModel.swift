//
//  WebsitePermissionsViewModel.swift
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
import FeatureFlags_macOS
import Foundation
import PixelKit
import PrivacyConfig

@MainActor
final class WebsitePermissionsViewModel: ObservableObject {
    private enum Constants {
        static let maximumRecentRows = 3
    }

    private struct PermissionKey: Hashable {
        let domain: String
        let permissionType: PermissionType

        init(_ entry: WebsitePermissionEntry) {
            domain = entry.domain
            permissionType = entry.permissionType
        }

        init(_ row: WebsitePermissionsViewState.RecentRow) {
            domain = row.domain
            permissionType = row.permissionType
        }
    }

    @Published
    private(set) var viewState = WebsitePermissionsViewState()

    private let permissionManager: PermissionManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let defaults: WebsitePermissionDefaultsProtocol
    private let pixelFiring: PixelFiring?
    private var permissionsCancellable: AnyCancellable?
    private var latestEntries = [WebsitePermissionEntry]()
    /// Recents changed on this page keep sorting by their previous date until the page closes.
    private var heldRecentDates = [PermissionKey: Date]()

    private var nativeVoiceFlowEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNativeVoicePermissionFlow)
    }

    init(
        permissionManager: PermissionManagerProtocol,
        featureFlagger: FeatureFlagger,
        defaults: WebsitePermissionDefaultsProtocol,
        pixelFiring: PixelFiring? = PixelKit.shared
    ) {
        self.permissionManager = permissionManager
        self.featureFlagger = featureFlagger
        self.defaults = defaults
        self.pixelFiring = pixelFiring
    }

    // MARK: - Public

    func send(action: Action) {
        switch action {
        case .onAppear:
            setupObserver()

        case .onDisappear:
            releaseHeldRecents()

        case .changeRecentDecision(let row, let decision):
            guard row.permissionType.isUserEditable(forDomain: row.domain, nativeVoiceFlowEnabled: nativeVoiceFlowEnabled),
                  decision != row.decision else { return }
            holdRecentInPlace(row)
            permissionManager.setPermission(decision, forDomain: row.domain, permissionType: row.permissionType)
            pixelFiring?.fire(PermissionPixel.settingsSiteChanged(permissionType: row.permissionType, to: decision), frequency: .dailyAndCount)

        case .removeRecent(let row):
            guard row.permissionType.isUserEditable(forDomain: row.domain, nativeVoiceFlowEnabled: nativeVoiceFlowEnabled) else { return }
            permissionManager.removePermission(forDomain: row.domain, permissionType: row.permissionType)
            pixelFiring?.fire(PermissionPixel.settingsSiteRemoved(permissionType: row.permissionType), frequency: .dailyAndCount)

        case .openDetail(let category):
            viewState.detailModel = WebsitePermissionDetailViewModel(
                initialState: makeDetailInitialState(for: category),
                permissionManager: permissionManager,
                featureFlagger: featureFlagger,
                defaults: defaults,
                pixelFiring: pixelFiring
            )
            pixelFiring?.fire(PermissionPixel.settingsDetailOpened(category: category), frequency: .dailyAndCount)

        case .closeDetail:
            viewState.detailModel = nil
        }
    }

    // MARK: - Private

    private func setupObserver() {
        guard permissionsCancellable == nil else { return }

        permissionsCancellable = permissionManager.persistedPermissionsPublisher
            .combineLatest(featureFlagger.updatesPublisher.prepend(()))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries, _ in
                guard let self else { return }
                latestEntries = entries
                let persistedKeys = Set(entries.map(PermissionKey.init))
                heldRecentDates = heldRecentDates.filter { persistedKeys.contains($0.key) }
                updateViewState()
            }
    }

    private func updateViewState() {
        let editableEntries = latestEntries.filter {
            $0.permissionType.isUserEditable(forDomain: $0.domain, nativeVoiceFlowEnabled: nativeVoiceFlowEnabled)
        }
        viewState = WebsitePermissionsViewState(
            recents: makeRecentRows(from: editableEntries),
            rows: makeRows(from: editableEntries),
            detailModel: viewState.detailModel
        )
    }

    private func holdRecentInPlace(_ row: WebsitePermissionsViewState.RecentRow) {
        let key = PermissionKey(row)
        guard heldRecentDates[key] == nil,
              let lastModified = latestEntries.first(where: { PermissionKey($0) == key })?.lastModified else { return }
        heldRecentDates[key] = lastModified
    }

    private func releaseHeldRecents() {
        guard !heldRecentDates.isEmpty else { return }
        heldRecentDates = [:]
        updateViewState()
    }

    private func makeRecentRows(from entries: [WebsitePermissionEntry]) -> [WebsitePermissionsViewState.RecentRow] {
        let categories = visibleCategories
        return entries
            .filter { entry in
                entry.lastModified != nil && categories.contains { $0.contains(entry.permissionType) }
            }
            .sorted(by: isOrderedBefore)
            .prefix(Constants.maximumRecentRows)
            .map(makeRecentRow)
    }

    private func makeDetailInitialState(for category: WebsitePermissionCategory) -> WebsitePermissionDetailViewState {
        WebsitePermissionDetailViewState(
            category: category,
            entries: latestEntries,
            featureFlagger: featureFlagger
        )
    }

    private func isOrderedBefore(_ first: WebsitePermissionEntry, _ second: WebsitePermissionEntry) -> Bool {
        let firstDate = sortDate(of: first)
        let secondDate = sortDate(of: second)
        if firstDate != secondDate {
            return (firstDate ?? .distantPast) > (secondDate ?? .distantPast)
        } else if first.domain != second.domain {
            return first.domain < second.domain
        } else {
            return first.permissionType.rawValue < second.permissionType.rawValue
        }
    }

    private func sortDate(of entry: WebsitePermissionEntry) -> Date? {
        heldRecentDates[PermissionKey(entry)] ?? entry.lastModified
    }

    private func makeRecentRow(from entry: WebsitePermissionEntry) -> WebsitePermissionsViewState.RecentRow {
        return .init(
            domain: entry.domain,
            permissionType: entry.permissionType,
            decision: entry.displayedDecision,
            permissionTitle: permissionTitle(for: entry.permissionType),
            availableDecisions: entry.permissionType.editableDecisions
        )
    }

    private func permissionTitle(for permissionType: PermissionType) -> String {
        guard permissionType.isExternalScheme else { return permissionType.localizedDescription }
        return String(format: UserText.websitePermissionsExternalAppFormat, permissionType.localizedDescription)
    }

    private var visibleCategories: [WebsitePermissionCategory] {
        WebsitePermissionCategory.allCases
    }

    private func makeRows(from entries: [WebsitePermissionEntry]) -> [WebsitePermissionsViewState.Row] {
        visibleCategories.map { category in
            WebsitePermissionsViewState.Row(
                category: category,
                count: entries.count { category.contains($0.permissionType) }
            )
        }
    }
}

extension WebsitePermissionsViewModel {
    enum Action {
        case onAppear
        case onDisappear
        case changeRecentDecision(WebsitePermissionsViewState.RecentRow, PersistedPermissionDecision)
        case removeRecent(WebsitePermissionsViewState.RecentRow)
        case openDetail(WebsitePermissionCategory)
        case closeDetail
    }
}
