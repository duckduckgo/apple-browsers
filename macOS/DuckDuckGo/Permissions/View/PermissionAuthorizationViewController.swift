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

import Cocoa
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

    @IBOutlet var descriptionLabel: NSTextField!
    @IBOutlet var domainNameLabel: NSTextField!
    @IBOutlet var alwaysAllowCheckbox: NSButton!
    @IBOutlet var alwaysAllowStackView: NSStackView!
    @IBOutlet var learnMoreStackView: NSStackView!
    @IBOutlet var denyButton: NSButton!
    @IBOutlet var buttonsBottomConstraint: NSLayoutConstraint!
    @IBOutlet var learnMoreBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var linkButton: LinkButton!
    @IBOutlet weak var allowButton: NSButton!

    private var swiftUIHostingView: NSHostingView<PermissionAuthorizationSwiftUIView>?
    private let newPermissionView: Bool

    /// Indicates whether the authorization flow is still in progress (user hasn't clicked Allow/Deny yet).
    /// This prevents the popover from being closed prematurely during two-step flows (e.g., geolocation).
    private(set) var isAuthorizationInProgress: Bool = false

    weak var query: PermissionAuthorizationQuery? {
        didSet {
            if newPermissionView {
                setupSwiftUIView()
            } else {
                updateText()
            }
        }
    }

    // Programmatic initializer for SwiftUI mode
    init(newPermissionView: Bool) {
        self.newPermissionView = newPermissionView
        super.init(nibName: nil, bundle: nil)
    }

    // Storyboard initializer
    required init?(coder: NSCoder) {
        self.newPermissionView = false
        super.init(coder: coder)
    }

    override func loadView() {
        if newPermissionView {
            // Create a simple container view for SwiftUI
            view = NSView()
        } else {
            // Load from nib/storyboard
            super.loadView()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if newPermissionView {
            setupSwiftUIView()
        } else {
            updateText()
        }
    }

    override func viewWillAppear() {
        guard !newPermissionView else { return }

        alwaysAllowCheckbox.state = .off
        if query?.shouldShowCancelInsteadOfDeny == true {
            denyButton.title = UserText.cancel
        } else {
            denyButton.title = UserText.permissionPopoverDenyButton
        }
        denyButton.setAccessibilityIdentifier("PermissionAuthorizationViewController.denyButton")
    }

    private func updateText() {
        guard !newPermissionView,
              isViewLoaded,
              let query = query,
              !query.permissions.isEmpty
        else { return }

        switch query.permissions[0] {
        case .camera, .microphone:
            descriptionLabel.stringValue = String(format: UserText.devicePermissionAuthorizationFormat,
                                                  query.domain,
                                                  query.permissions.localizedDescription.lowercased())
        case .popups:
            descriptionLabel.stringValue = String(format: UserText.popupWindowsPermissionAuthorizationFormat,
                                                  query.domain,
                                                  query.permissions.localizedDescription.lowercased())
        case .notification:
            descriptionLabel.stringValue = String(format: UserText.devicePermissionAuthorizationFormat,
                                                  query.domain,
                                                  query.permissions.localizedDescription.lowercased())
        case .externalScheme where query.domain.isEmpty:
            descriptionLabel.stringValue = String(format: UserText.externalSchemePermissionAuthorizationNoDomainFormat,
                                                  query.permissions.localizedDescription)
        case .externalScheme:
            descriptionLabel.stringValue = String(format: UserText.externalSchemePermissionAuthorizationFormat,
                                                  query.domain,
                                                  query.permissions.localizedDescription)
        case .geolocation:
            descriptionLabel.stringValue = String(format: UserText.locationPermissionAuthorizationFormat, query.domain)
        }
        alwaysAllowCheckbox.title = UserText.permissionAlwaysAllowOnDomainCheckbox
        domainNameLabel.stringValue = query.domain.isEmpty ? "" : "“" + query.domain + "”"
        alwaysAllowStackView.isHidden = !query.shouldShowAlwaysAllowCheckbox
        learnMoreStackView.isHidden = !query.permissions.contains(.geolocation)
        learnMoreBottomConstraint.isActive = !learnMoreStackView.isHidden
        buttonsBottomConstraint.isActive = !learnMoreBottomConstraint.isActive
        linkButton.title = UserText.permissionPopupLearnMoreLink
        allowButton.title = UserText.permissionPopupAllowButton
        allowButton.setAccessibilityIdentifier("PermissionAuthorizationViewController.allowButton")
    }

    @IBAction func alwaysAllowLabelClick(_ sender: Any) {
        guard !newPermissionView else { return }
        alwaysAllowCheckbox.setNextState()
    }

    @IBAction func grantAction(_ sender: NSButton) {
        guard !newPermissionView else { return }
        self.dismiss()
        query?.handleDecision(grant: true, remember: query!.shouldShowAlwaysAllowCheckbox && alwaysAllowCheckbox.state == .on)
    }

    @IBAction func denyAction(_ sender: NSButton) {
        guard !newPermissionView else { return }
        self.dismiss()
        guard let query = query,
              !query.shouldShowCancelInsteadOfDeny
        else { return }

        query.handleDecision(grant: false)
    }

    @IBAction func learnMoreAction(_ sender: NSButton) {
        guard !newPermissionView else { return }
        Application.appDelegate.windowControllersManager.show(url: "https://help.duckduckgo.com/privacy/device-location-services".url, source: .ui, newTab: true)
    }

    // MARK: - SwiftUI View Setup

    private func setupSwiftUIView() {
        guard newPermissionView, let query = query, !query.permissions.isEmpty else { return }

        // Remove all existing subviews to ensure clean state
        view.subviews.forEach { $0.removeFromSuperview() }
        swiftUIHostingView = nil

        let permissionType = PermissionAuthorizationType(from: query.permissions)
        let swiftUIView = PermissionAuthorizationSwiftUIView(
            domain: query.domain,
            permissionType: permissionType,
            onDeny: { [weak self] in
                self?.handleDeny()
            },
            onAllow: { [weak self] in
                self?.handleAllow()
            },
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
        dismiss()
        query?.handleDecision(grant: false, remember: nil)
    }

    private func handleAllow() {
        isAuthorizationInProgress = false
        dismiss()
        query?.handleDecision(grant: true, remember: nil)
    }
}
