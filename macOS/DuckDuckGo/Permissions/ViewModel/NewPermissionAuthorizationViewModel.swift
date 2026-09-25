//
//  NewPermissionAuthorizationViewModel.swift
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
import PixelKit

@MainActor
final class NewPermissionAuthorizationViewModel: ObservableObject {
    @Published
    private(set) var viewState: NewPermissionAuthorizationViewState

    private weak var query: PermissionAuthorizationQuery?
    private let domain: String
    private let permissions: [PermissionType]
    private let permissionType: PermissionAuthorizationType
    private let pixelFiring: PixelFiring?
    private let openURL: (URL) -> Void
    private let finish: () -> Void

    init(
        initialState: NewPermissionAuthorizationViewState? = .init(),
        query: PermissionAuthorizationQuery,
        pixelFiring: PixelFiring? = PixelKit.shared,
        openURL: @escaping (URL) -> Void,
        finish: @escaping () -> Void
    ) {
        viewState = initialState ?? .init()
        self.query = query
        self.domain = query.domain
        self.permissions = query.permissions
        self.permissionType = PermissionAuthorizationType(from: query.permissions)
        self.pixelFiring = pixelFiring
        self.openURL = openURL
        self.finish = finish
    }

    // MARK: - Public

    func send(action: Action) {
        switch action {
        case .onAppear:
            viewState.title = makeTitle()
            viewState.learnMore = permissionType.learnMoreURL.map {
                NewPermissionAuthorizationViewState.LearnMore(title: UserText.permissionPopupLearnMoreLink, url: $0)
            }

        case .allowThisVisit:
            submit(.allowThisVisit)

        case .alwaysAllow:
            submit(.alwaysAllow)

        case .neverAllow:
            submit(.neverAllow)

        case .dismiss:
            query?.cancel()
            finish()

        case .learnMore:
            guard let url = viewState.learnMore?.url else { return }
            openURL(url)
        }
    }

    // MARK: - Private

    private func submit(_ decision: PermissionPromptDecision) {
        defer { finish() }
        guard let query else { return }

        let output = decision.output
        for permission in permissions {
            pixelFiring?.fire(PermissionPixel.authorizationDecision(permissionType: permission, decision: output.granted ? .allow : .deny))
        }
        query.handleDecision(grant: output.granted, remember: output.remember)
    }

    private func makeTitle() -> String {
        switch permissionType {
        case .geolocation:
            return String(format: UserText.websitePermissionsPromptLocationFormat, domain)
        case .camera, .microphone, .cameraAndMicrophone:
            return String(format: UserText.websitePermissionsPromptDeviceFormat, domain, permissionType.localizedDescription.lowercased())
        case .notification:
            return String(format: UserText.websitePermissionsPromptNotificationsFormat, domain)
        case .popups:
            return String(format: UserText.popupWindowsPermissionAuthorizationFormat, domain, permissionType.localizedDescription.lowercased())
        case .externalScheme:
            if domain.isEmpty {
                return String(format: UserText.externalSchemePermissionAuthorizationNoDomainFormat, permissionType.localizedDescription)
            }
            return String(format: UserText.externalSchemePermissionAuthorizationFormat, domain, permissionType.localizedDescription)
        }
    }
}

extension NewPermissionAuthorizationViewModel {
    enum Action {
        case onAppear
        case allowThisVisit
        case alwaysAllow
        case neverAllow
        case dismiss
        case learnMore
    }
}
