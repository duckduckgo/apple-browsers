//
//  ProductSurfaceTelemtry.swift
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

import BrowserServicesKit

protocol ProductSurfaceTelemetry {

    ///  Called when the menu is used, either on new tab page or when browsing.
    func menuUsed()

}

struct PixelProductSurfaceTelemetry: ProductSurfaceTelemetry {

     private let featureFlagger: FeatureFlagger
     private let dailyPixelFiring: DailyPixelFiring.Type

     func menuUsed() {
         guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
         dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageMenu, error: nil, withAdditionalParameters: [:])
     }

}
