//
//  EmailConfirmationJobProvider.swift
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
import Common
import os.log

public protocol EmailConfirmationJobProviding {
    func createEmailConfirmationJobs(showWebView: Bool,
                                     errorDelegate: EmailConfirmationErrorDelegate,
                                     jobDependencies: EmailConfirmationJobDependencyProviding) throws -> [EmailConfirmationJob]
}

public final class EmailConfirmationJobProvider: EmailConfirmationJobProviding {
    public init() {}

    public func createEmailConfirmationJobs(showWebView: Bool,
                                            errorDelegate: EmailConfirmationErrorDelegate,
                                            jobDependencies: EmailConfirmationJobDependencyProviding) throws -> [EmailConfirmationJob] {
        let confirmations = try jobDependencies.database.fetchOptOutEmailConfirmationsWithLink()
        Logger.dataBrokerProtection.log("✉️ [EmailConfirmationJobProvider] Fetched \(confirmations.count, privacy: .public) email confirmations")

        let validConfirmations = confirmations.filter { $0.emailConfirmationAttemptCount < 3 }
        Logger.dataBrokerProtection.log("✉️ [EmailConfirmationJobProvider] \(validConfirmations.count, privacy: .public) confirmations are below max retry limit")

        let sorted = validConfirmations.sorted { lhs, rhs in
            let date1 = lhs.emailConfirmationLinkObtainedOnBEDate ?? .distantFuture
            let date2 = rhs.emailConfirmationLinkObtainedOnBEDate ?? .distantFuture
            return date1 < date2
        }
        Logger.dataBrokerProtection.log("✉️ [EmailConfirmationJobProvider] Jobs sorted by link obtained date (oldest first)")

        return sorted.map { jobData in
            EmailConfirmationJob(jobData: jobData,
                                 showWebView: showWebView,
                                 errorDelegate: errorDelegate,
                                 jobDependencies: jobDependencies)
        }
    }
}
