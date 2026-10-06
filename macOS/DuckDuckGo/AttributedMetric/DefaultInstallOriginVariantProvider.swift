//
//  DefaultInstallOriginVariantProvider.swift
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

import AttributedMetric
import Foundation
import SERPInstallOrigin

final class DefaultInstallOriginVariantProvider: InstallOriginVariantProviding {

    private let originProvider: AttributedMetricOriginProvider
    private let installDateProvider: any AttributedMetricInstallDateProviding
    private let dateProvider: any DateProviding

    init(originProvider: AttributedMetricOriginProvider = DefaultAttributedMetricOriginProvider(loadOrigin: {
        getXattr(named: AttributionXattr.origin, from: Bundle.main.bundlePath)
    }),
         installDateProvider: any AttributedMetricInstallDateProviding = AttributedMetricATBInstallDateProvider(),
         dateProvider: any DateProviding = DefaultDateProvider()) {
        self.originProvider = originProvider
        self.installDateProvider = installDateProvider
        self.dateProvider = dateProvider
    }

    func installOriginVariant(forCampaign campaign: String?) -> String? {
        guard let origin = originProvider.origin,
              let installDate = installDateProvider.installDate,
              let campaign,
              !campaign.isEmpty else {
            return nil
        }

        return InstallOriginVariantResolver.variant(
            origin: origin,
            requestedCampaign: campaign,
            installDate: installDate,
            referenceDate: dateProvider.now()
        )
    }
}
