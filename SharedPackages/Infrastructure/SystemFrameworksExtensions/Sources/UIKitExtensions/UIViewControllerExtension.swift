//
//  UIViewControllerExtension.swift
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

@_exported import UIKit

public extension UIViewController {

    /// Returns the deepest view controller in this controller's presentation stack.
    ///
    /// The search starts from `self.presentedViewController` and follows the
    /// `presentedViewController` chain until the last presented controller
    /// (i.e., the one currently visible on top) is found.
    ///
    /// - Returns: The top-most presented `UIViewController`, or `nil` if this
    ///   controller is not presenting anything.
    func topMostPresentedViewController() -> UIViewController? {
        var topController = self.presentedViewController

        while let presentedViewController = topController?.presentedViewController {
            topController = presentedViewController
        }

        return topController
    }

}
