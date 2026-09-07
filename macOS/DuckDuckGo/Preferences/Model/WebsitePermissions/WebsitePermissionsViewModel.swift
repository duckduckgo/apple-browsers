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

@MainActor
final class WebsitePermissionsViewModel: ObservableObject {
    private enum Constants {
        /// The design shows at most three recently changed permissions.
        static let maximumRecentRows = 3
    }

    @Published
    private(set) var viewState = WebsitePermissionsViewState()

    private let permissionManager: WebsitePermissionManaging
    private var permissionsCancellable: AnyCancellable?
    private var didAppear = false

    init(permissionManager: WebsitePermissionManaging) {
        self.permissionManager = permissionManager
    }

    // MARK: - Public

    func send(action: Action) {
        switch action {
        case .onAppear:
            guard !didAppear else { return }
            didAppear = true
            viewState.rows = makeRows(from: [])
            setupObserver()
        case .changeRecentDecision(let row, let decision):
            guard decision != row.decision else { return }
            permissionManager.setPermission(decision, forDomain: row.domain, permissionType: row.permissionType)
        case .removeRecent(let row):
            permissionManager.removePermission(forDomain: row.domain, permissionType: row.permissionType)
        }
    }

    // MARK: - Private

    private func setupObserver() {
        guard permissionsCancellable == nil else { return }

        permissionsCancellable = permissionManager.persistedPermissionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                guard let self else { return }
                viewState.recents = makeRecentRows(from: entries)
                viewState.rows = makeRows(from: entries)
            }
    }

    /// The most recently changed decisions, newest first. Entries without a `lastModified` predate the
    /// stored timestamp, so they are excluded rather than being presented as recent.
    private func makeRecentRows(from entries: [WebsitePermissionEntry]) -> [WebsitePermissionsViewState.RecentRow] {
        entries
            .filter { entry in
                entry.lastModified != nil && WebsitePermissionCategory.category(for: entry.permissionType) != nil
            }
            .sorted(by: Self.isMoreRecent)
            .prefix(Constants.maximumRecentRows)
            .map(makeRecentRow)
    }

    /// Orders by recency, falling back to domain then permission so equal timestamps stay stable.
    private static func isMoreRecent(_ lhs: WebsitePermissionEntry, _ rhs: WebsitePermissionEntry) -> Bool {
        guard let lhsDate = lhs.lastModified, let rhsDate = rhs.lastModified else {
            return lhs.lastModified != nil
        }
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        if lhs.domain != rhs.domain {
            return lhs.domain < rhs.domain
        }
        return lhs.permissionType.rawValue < rhs.permissionType.rawValue
    }

    private func makeRecentRow(from entry: WebsitePermissionEntry) -> WebsitePermissionsViewState.RecentRow {
        WebsitePermissionsViewState.RecentRow(
            domain: entry.domain,
            permissionType: entry.permissionType,
            decision: entry.decision,
            permissionTitle: Self.permissionTitle(for: entry.permissionType),
            availableDecisions: Self.availableDecisions(for: entry.permissionType, decision: entry.decision))
    }

    private static func permissionTitle(for permissionType: PermissionType) -> String {
        guard permissionType.isExternalScheme else { return permissionType.localizedDescription }
        return String(format: UserText.websitePermissionsExternalAppFormat, permissionType.localizedDescription)
    }

    /// Pop-ups cannot persist a denied decision, so they only offer Ask and Allow — unless one was
    /// already stored, in which case it stays selectable so the user can see and change it.
    private static func availableDecisions(for permissionType: PermissionType,
                                           decision: PersistedPermissionDecision) -> [PersistedPermissionDecision] {
        guard permissionType.canPersistDeniedDecision || decision == .deny else {
            return [.ask, .allow]
        }
        return [.deny, .ask, .allow]
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
