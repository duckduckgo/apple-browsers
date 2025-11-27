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
import BrowserServicesKit
import FeatureFlags

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

    var featureFlagger: FeatureFlagger?

    weak var query: PermissionAuthorizationQuery? {
        didSet {
            updateText()
            setupSwiftUIViewIfNeeded()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if featureFlagger?.isFeatureOn(.newPermissionView) == true {
            setupSwiftUIViewIfNeeded()
        } else {
            updateText()
        }
    }

    override func viewWillAppear() {
        alwaysAllowCheckbox.state = .off
        if query?.shouldShowCancelInsteadOfDeny == true {
            denyButton.title = UserText.cancel
        } else {
            denyButton.title = UserText.permissionPopoverDenyButton
        }
        denyButton.setAccessibilityIdentifier("PermissionAuthorizationViewController.denyButton")
    }

    private func updateText() {
        guard isViewLoaded,
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
        alwaysAllowCheckbox.setNextState()
    }

    @IBAction func grantAction(_ sender: NSButton) {
        self.dismiss()
        query?.handleDecision(grant: true, remember: query!.shouldShowAlwaysAllowCheckbox && alwaysAllowCheckbox.state == .on)
    }

    @IBAction func denyAction(_ sender: NSButton) {
        self.dismiss()
        guard let query = query,
              !query.shouldShowCancelInsteadOfDeny
        else { return }

        query.handleDecision(grant: false)
    }

    @IBAction func learnMoreAction(_ sender: NSButton) {
        Application.appDelegate.windowControllersManager.show(url: "https://help.duckduckgo.com/privacy/device-location-services".url, source: .ui, newTab: true)
    }

    // Mark: - New Authorization View

    private var swiftUIHostingView: NSHostingView<PermissionAuthorizationSwiftUIView>?

    private func setupSwiftUIViewIfNeeded() {
        guard isViewLoaded,
              let query = query,
              !query.permissions.isEmpty,
              query.permissions.contains(.geolocation),
              let featureFlagger = featureFlagger,
              featureFlagger.isFeatureOn(.newPermissionView)
        else {
            // Hide SwiftUI view if it exists but shouldn't be shown
            swiftUIHostingView?.isHidden = true
            return
        }

        // Hide storyboard-based UI elements
        descriptionLabel?.isHidden = true
        domainNameLabel?.isHidden = true
        alwaysAllowCheckbox?.isHidden = true
        alwaysAllowStackView?.isHidden = true
        learnMoreStackView?.isHidden = true
        denyButton?.isHidden = true
        allowButton?.isHidden = true
        linkButton?.isHidden = true

        // Create SwiftUI view if it doesn't exist
        if swiftUIHostingView == nil {
            let swiftUIView = PermissionAuthorizationSwiftUIView(
                domain: query.domain,
                onNeverAllow: { [weak self] in
                    self?.handleNeverAllow()
                },
                onAlwaysAllow: { [weak self] in
                    self?.handleAlwaysAllow()
                }
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
            
            // Update preferred content size for the popover
            preferredContentSize = NSSize(width: 400, height: 160)
        } else {
            swiftUIHostingView?.isHidden = false
        }
    }

    private func handleNeverAllow() {
        dismiss()
        query?.handleDecision(grant: false)
    }

    private func handleAlwaysAllow() {
        dismiss()
        query?.handleDecision(grant: true, remember: true)
    }
}
