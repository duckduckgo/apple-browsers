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

import PixelKit
import PixelExperimentKit
import PixelExperimentKitTestUtils

#if DEBUG
extension PixelKit {

    /// Helps our automated tests set up PixelKit for experiment testing support
    ///
    /// The reason this is not in the unit test target or in a separate module is because we need this setup to run
    /// in the target process we want to configure.
    ///
    /// More information in:
    ///
    static func configureExperimentsForTesting() {
        let mockPixelStore = MockExperimentActionPixelStore()
        let mockFeatureFlagger = MockFeatureFlagger()

        PixelKit.configureExperimentKit(
            featureFlagger: mockFeatureFlagger,
            eventTracker: ExperimentEventTracker(store: mockPixelStore)) { _, _, _ in }
    }
}
#endif
