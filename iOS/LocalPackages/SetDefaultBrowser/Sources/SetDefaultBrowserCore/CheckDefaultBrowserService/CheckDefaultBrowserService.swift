//
//  CheckDefaultBrowserService.swift
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
import class UIKit.UIApplication

// MARK: - DefaultBrowserChecker

public enum CheckDefaultBrowserServiceError: Error, Equatable {
    case notSupportedOnThisOSVersion
    case maxNumberOfAttemptsExceeded(nextRetryDate: Date?)
    case unknownError(NSError)
}

@MainActor
public protocol CheckDefaultBrowserService: AnyObject {
    func isDefaultWebBrowser() -> Result<Bool, CheckDefaultBrowserServiceError>
}

// Wrapper on UIApplication.
// `isDefault(_ category: UIApplication.Category) throws -> Bool` is supported only on iOS 18.2+.
// Usually we would make an interface with the same method and have UIApplication conform to it.
// The issue with the above approach is that it requires marking the protocol `@available(iOS 18.2, *)`.
// That will cause issues with injecting the parameter as it is available only for iOS 18.2.
@MainActor
public protocol ApplicationDefaultCategoryChecking: AnyObject {
    @available(iOS 18.2, *)
    func isDefault(_ category: UIApplication.Category) throws -> Bool
}

extension UIApplication: ApplicationDefaultCategoryChecking {}

@MainActor
public final class SystemCheckDefaultBrowserService: CheckDefaultBrowserService {
    private let application: ApplicationDefaultCategoryChecking

    public init(application: ApplicationDefaultCategoryChecking = UIApplication.shared) {
        self.application = application
    }

    public func isDefaultWebBrowser() -> Result<Bool, CheckDefaultBrowserServiceError> {
        guard #available(iOS 18.2, *) else { return .failure(.notSupportedOnThisOSVersion) }

        do {
            let isDefaultBrowser = try application.isDefault(.webBrowser)
            return .success(isDefaultBrowser)
        } catch let error as NSError where error.domain == UIApplication.CategoryDefaultError.errorDomain && error.code == UIApplication.CategoryDefaultError.Code.rateLimited.rawValue {
            // Max attempts of getting a result in a year reached.
            // See: https://developer.apple.com/documentation/UIKit/UIApplication/isDefault(_:)
            let nextRetryDate = error.userInfo[UIApplication.CategoryDefaultError.retryAvailableDateErrorKey] as? Date
            return .failure(CheckDefaultBrowserServiceError.maxNumberOfAttemptsExceeded(nextRetryDate: nextRetryDate))
        } catch {
            return .failure(CheckDefaultBrowserServiceError.unknownError(error as NSError))
        }
    }
}
