//
//  VPNUIPresenting.swift
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

protocol VPNUIPresenting {
    @MainActor
    func showVPNAppExclusions()

    @MainActor
    func showVPNAppExclusions(addApp: Bool)

    @MainActor
    func showVPNDomainExclusions()

    @MainActor
    func showVPNDomainExclusions(domain: String?)
}

extension WindowControllersManager: VPNUIPresenting {

    @MainActor
    func showVPNAppExclusions() {
        showVPNAppExclusions(addApp: false)
    }

    @MainActor
    func showVPNAppExclusions(addApp: Bool) {
        showPreferencesTab(withSelectedPane: .vpn)

        let viewController = ExcludedAppsViewController.create()
        let windowController = viewController.wrappedInWindowController()

        guard let window = windowController.window, let parentWindowController = lastKeyMainWindowController else {
            assertionFailure("Failed to present ExcludedAppsViewController")
            return
        }

        parentWindowController.window?.beginSheet(window)
        if addApp {
            viewController.addApp()
        }
    }

    @MainActor
    func showVPNDomainExclusions() {
        showVPNDomainExclusions(domain: nil)
    }

    @MainActor
    func showVPNDomainExclusions(domain: String?) {
        showPreferencesTab(withSelectedPane: .vpn)

        let viewController = ExcludedDomainsViewController.create()
        let windowController = viewController.wrappedInWindowController()

        guard let window = windowController.window, let parentWindowController = lastKeyMainWindowController else {
            assertionFailure("Failed to present ExcludedDomainsViewController")
            return
        }

        parentWindowController.window?.beginSheet(window)

        if let domain {
            viewController.addDomain(domain: domain)
        }
    }
}
