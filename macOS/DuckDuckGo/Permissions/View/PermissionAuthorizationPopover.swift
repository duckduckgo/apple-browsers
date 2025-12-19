//
//  PermissionAuthorizationPopover.swift
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

final class PermissionAuthorizationPopover: NSPopover {

    @nonobjc private var didShow: Bool = false
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
        super.init()

        behavior = .applicationDefined
        setupContentController()
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("PermissionAuthorizationPopover: Bad initializer")
    }

    deinit {
#if DEBUG
        // Check that our content view controller deallocates
        contentViewController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    // swiftlint:disable force_cast
    var viewController: PermissionAuthorizationViewController {
        get {
            // Ensure content controller is set up
            if contentViewController == nil {
                setupContentController()
            }
            return contentViewController as! PermissionAuthorizationViewController
        }
    }
    // swiftlint:enable force_cast

    private func setupContentController() {
        let controller: PermissionAuthorizationViewController

        if featureFlagger.isFeatureOn(.newPermissionView) {
            // Create programmatically
            controller = PermissionAuthorizationViewController(newPermissionView: true)
        } else {
            // Load from storyboard
            controller = setupStoryboardController()
        }

        contentViewController = controller
    }

    // swiftlint:disable force_cast
    private func setupStoryboardController() -> PermissionAuthorizationViewController {
        let storyboard = NSStoryboard(name: "PermissionAuthorization", bundle: nil)
        return storyboard
            .instantiateController(withIdentifier: "PermissionAuthorizationViewController") as! PermissionAuthorizationViewController
    }
    // swiftlint:enable force_cast

}

extension PermissionAuthorizationPopover: NSPopoverDelegate {

    func popoverWillShow(_ notification: Notification) {
        self.didShow = false
    }

    func popoverDidShow(_ notification: Notification) {
        self.didShow = true
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard didShow else { return false } // don't close on mouse-up
        return true
    }

}
