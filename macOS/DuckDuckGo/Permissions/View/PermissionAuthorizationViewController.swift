//
//  PermissionAuthorizationViewController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Cocoa
import PixelKit
import SwiftUI

extension PermissionType {
    var localizedDescription: String {
        switch self {
        case .camera:
            return UserText.permissionCamera
        case .microphone:
            return UserText.permissionMicrophone
        case .geolocation:
            return UserText.permissionGeolocation
        case .popups:
            return UserText.permissionPopups
        case .notification:
            return UserText.permissionNotification
        case .externalScheme(scheme: let scheme):
            guard let url = URL(string: scheme + URL.NavigationalScheme.separator),
                  let app = NSWorkspace.shared.application(toOpen: url)
            else { return scheme }

            return app
        case .autoplayPolicy:
            return UserText.permissionAutoplay
        }
    }
}

extension Array where Element == PermissionType {

    var localizedDescription: String {
        if Set(self) == Set([.camera, .microphone]) {
            return UserText.permissionCameraAndMicrophone
        } else if self.count == 1 {
            return self[0].localizedDescription
        }
        assertionFailure("Unexpected Permissions combination")
        return self.map(\.localizedDescription).joined(separator: ", ")
    }

}

final class PermissionAuthorizationViewController: NSViewController {

    let systemPermissionManager = SystemPermissionManager()

    private var swiftUIHostingView: NSHostingView<PermissionAuthorizationSwiftUIView>?

    /// Indicates whether the authorization flow is still in progress (user hasn't clicked Allow/Deny yet).
    /// This prevents the popover from being closed prematurely during two-step flows (e.g., geolocation).
    private(set) var isAuthorizationInProgress: Bool = false

    weak var query: PermissionAuthorizationQuery? {
        didSet {
            setupSwiftUIView()
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PermissionAuthorizationViewController: Use init() instead")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSwiftUIView()
    }

    // MARK: - SwiftUI View Setup

    private func setupSwiftUIView() {
        guard let query = query, !query.permissions.isEmpty else { return }

        // Remove all existing subviews to ensure clean state
        view.subviews.forEach { $0.removeFromSuperview() }
        swiftUIHostingView = nil

        let permissionType = PermissionAuthorizationType(from: query.permissions)
        let showsTwoStepUI = permissionType.requiresSystemPermission
            && systemPermissionManager.isAuthorizationRequired(for: permissionType.asPermissionType)

        let swiftUIView = PermissionAuthorizationSwiftUIView(
            domain: query.domain,
            permissionType: permissionType,
            showsTwoStepUI: showsTwoStepUI,
            isSystemPermissionDisabled: query.isSystemPermissionDisabled,
            onDeny: { [weak self] in
                self?.handleDeny()
            },
            onAllow: { [weak self] in
                self?.handleAllow()
            },
            onDismiss: { [weak self] in
                self?.handleDismiss()
            },
            onLearnMore: permissionType.learnMoreURL != nil ? {
                if let url = permissionType.learnMoreURL {
                    Application.appDelegate.windowControllersManager.show(url: url, source: .ui, newTab: true)
                }
            } : nil,
            systemPermissionManager: systemPermissionManager
        )

        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        swiftUIHostingView = hostingView
        isAuthorizationInProgress = true
    }

    private func handleDeny() {
        isAuthorizationInProgress = false
        fireAuthorizationPixel(decision: .deny)
        dismiss()
        query?.handleDecision(grant: false, remember: nil)
    }

    private func handleAllow() {
        isAuthorizationInProgress = false
        fireAuthorizationPixel(decision: .allow)
        dismiss()
        // For duck.ai microphone, persist "always allow" so voice chat doesn't re-prompt on every session.
        // Skip in Fire Windows — permissions there must not survive the window's lifetime.
        let alwaysRemember = query?.isBurner != true
            && query?.permissions.contains(.microphone) == true
            && query?.domain.isDuckAIHost == true
        query?.handleDecision(grant: true, remember: alwaysRemember ? true : nil)
    }

    private func handleDismiss() {
        isAuthorizationInProgress = false
        query?.cancel()
        dismiss()
    }

    private func fireAuthorizationPixel(decision: PermissionPixel.AuthorizationDecision) {
        guard let query = query else { return }
        // Fire pixel for each permission type in the query
        for permissionType in query.permissions {
            PixelKit.fire(PermissionPixel.authorizationDecision(permissionType: permissionType, decision: decision))
        }
    }
}
