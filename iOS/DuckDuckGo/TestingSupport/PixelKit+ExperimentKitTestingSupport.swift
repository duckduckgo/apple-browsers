//
//  PixelKit+ExperimentKitTestingSupport.swift
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

#if DEBUG
import BrowserServicesKit
import PixelKit
import PixelExperimentKit

extension PixelKit {

    /// Helps our automated tests set up PixelKit for experiment testing support
    ///
    /// The reason this is not in the unit test target or in a separate module is because we need to
    /// execute this code in the main app during testing as otherwise the static configuration for
    /// PixelExperimentKit won't work.
    ///
    /// The issue is explained in more detail in [this task](https://app.asana.com/1/137249556945/project/1208889145294658/task/1210054230046600?focus=true)
    ///
    static func configureExperimentsForTesting(
        pixelStore: ExperimentActionPixelStore,
        featureFlagger: FeatureFlagger) {

        PixelKit.configureExperimentKit(
            featureFlagger: featureFlagger,
            eventTracker: ExperimentEventTracker(store: pixelStore)) { _, _, _ in }
    }
}
#endif
