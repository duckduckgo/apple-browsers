//
//  DaxLogoManager.swift
//  DuckDuckGo
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

import Foundation
import UIKit
import SwiftUI

/// Manages the Dax logo view display and positioning
final class DaxLogoManager {
    
    // MARK: - Properties

    private var daxLogoHostingController: UIHostingController<FullHeightLogoView>?

    var logoView: UIView? {
        daxLogoHostingController?.view
    }
    
    // MARK: - Public Methods
    
    func installInViewController(_ viewController: UIViewController, belowView topView: UIView) {
        let daxLogoView = FullHeightLogoView()
        let hostingController = UIHostingController(rootView: daxLogoView)
        daxLogoHostingController = hostingController
        
        hostingController.view.backgroundColor = .clear
        viewController.addChild(hostingController)
        viewController.view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        let centeringGuide = UILayoutGuide()
        viewController.view.addLayoutGuide(centeringGuide)

        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: centeringGuide.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: centeringGuide.trailingAnchor),
            topView.bottomAnchor.constraint(equalTo: centeringGuide.topAnchor),
            viewController.view.keyboardLayoutGuide.topAnchor.constraint(equalTo: centeringGuide.bottomAnchor),

            hostingController.view.centerXAnchor.constraint(equalTo: centeringGuide.centerXAnchor),
            hostingController.view.centerYAnchor.constraint(equalTo: centeringGuide.centerYAnchor),
            hostingController.view.topAnchor.constraint(greaterThanOrEqualTo: centeringGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(lessThanOrEqualTo: centeringGuide.bottomAnchor)
        ])

        viewController.view.sendSubviewToBack(hostingController.view)
        hostingController.didMove(toParent: viewController)
    }
    
    func removeFromParent() {
        daxLogoHostingController?.willMove(toParent: nil)
        daxLogoHostingController?.view.removeFromSuperview()
        daxLogoHostingController?.removeFromParent()
        daxLogoHostingController = nil
    }
}


// Makes the logo view expand to fill the full height,
// allowing to automatically adjust for keyboard.
private struct FullHeightLogoView: View {
    var body: some View {
        NewTabPageDaxLogoView()
            .padding(24)
            .scaledToFit()
    }
}
