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
        }
    }

    // MARK: - Private

    private func setupObserver() {
        guard permissionsCancellable == nil else { return }

        permissionsCancellable = permissionManager.persistedPermissionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                guard let self else { return }
                viewState.rows = makeRows(from: entries)
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
    }
}
