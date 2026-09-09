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
import Foundation
import PrivacyConfig

@MainActor
final class WebsitePermissionsViewModel: ObservableObject {
    private enum Constants {
        static let maximumRecentRows = 3
    }

    @Published
    private(set) var viewState = WebsitePermissionsViewState()

    private let permissionManager: PermissionManagerProtocol
    private let featureFlagger: FeatureFlagger
    private var permissionsCancellable: AnyCancellable?

    init(permissionManager: PermissionManagerProtocol, featureFlagger: FeatureFlagger) {
        self.permissionManager = permissionManager
        self.featureFlagger = featureFlagger
    }

    // MARK: - Public

    func send(action: Action) {
        switch action {
        case .onAppear:
            setupObserver()

        case .changeRecentDecision(let row, let decision):
            guard row.permissionType.isUserEditable(forDomain: row.domain, featureFlagger: featureFlagger),
                  decision != row.decision else { return }
            permissionManager.setPermission(decision, forDomain: row.domain, permissionType: row.permissionType)

        case .removeRecent(let row):
            guard row.permissionType.isUserEditable(forDomain: row.domain, featureFlagger: featureFlagger) else { return }
            permissionManager.removePermission(forDomain: row.domain, permissionType: row.permissionType)
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
                let editableEntries = entries.filter {
                    $0.permissionType.isUserEditable(forDomain: $0.domain, featureFlagger: self.featureFlagger)
                }
                viewState = WebsitePermissionsViewState(
                    recents: makeRecentRows(from: editableEntries),
                    rows: makeRows(from: editableEntries))
            }
    }

    private func makeRecentRows(from entries: [WebsitePermissionEntry]) -> [WebsitePermissionsViewState.RecentRow] {
        entries
            .filter { entry in
                entry.lastModified != nil && WebsitePermissionCategory.category(for: entry.permissionType) != nil
            }
            .sorted(by: isOrderedBefore)
            .prefix(Constants.maximumRecentRows)
            .map(makeRecentRow)
    }

    private func isOrderedBefore(_ first: WebsitePermissionEntry, _ second: WebsitePermissionEntry) -> Bool {
        if first.lastModified != second.lastModified {
            return (first.lastModified ?? .distantPast) > (second.lastModified ?? .distantPast)
        } else if first.domain != second.domain {
            return first.domain < second.domain
        } else {
            return first.permissionType.rawValue < second.permissionType.rawValue
        }
    }

    private func makeRecentRow(from entry: WebsitePermissionEntry) -> WebsitePermissionsViewState.RecentRow {
        // Unsupported saved denials behave as Always Ask, as they do in Permission Center.
        let decision: PersistedPermissionDecision = entry.decision == .deny && !entry.permissionType.canPersistDeniedDecision ? .ask : entry.decision
        return .init(
            domain: entry.domain,
            permissionType: entry.permissionType,
            decision: decision,
            permissionTitle: permissionTitle(for: entry.permissionType),
            availableDecisions: availableDecisions(for: entry.permissionType)
        )
    }

    private func permissionTitle(for permissionType: PermissionType) -> String {
        guard permissionType.isExternalScheme else { return permissionType.localizedDescription }
        return String(format: UserText.websitePermissionsExternalAppFormat, permissionType.localizedDescription)
    }

    private func availableDecisions(for permissionType: PermissionType) -> [PersistedPermissionDecision] {
        if permissionType.canPersistDeniedDecision {
            return [.ask, .allow, .deny]
        } else {
            return [.ask, .allow]
        }
    }

    private func makeRows(from entries: [WebsitePermissionEntry]) -> [WebsitePermissionsViewState.Row] {
        WebsitePermissionCategory.allCases.map { category in
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
        case changeRecentDecision(WebsitePermissionsViewState.RecentRow, PersistedPermissionDecision)
        case removeRecent(WebsitePermissionsViewState.RecentRow)
    }
}
