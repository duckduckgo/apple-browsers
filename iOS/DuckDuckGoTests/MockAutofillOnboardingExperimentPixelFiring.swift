//
//  MockAutofillOnboardingExperimentPixelFiring.swift
//  DuckDuckGo
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

@testable import DuckDuckGo

final class MockAutofillOnboardingExperimentPixelFiring: AutofillOnboardingExperimentPixelFiring {
    func fireSaveTap() {}
    func fireDismissTap() {}
    func fireNeverAskTap() {}
    func firePasswordsSaved() {}
    func fireImportCompleted() {}
    func fireAutofillEnabled(_ enabled: Bool) {}
    func fireSyncEnabled(_ enabled: Bool) {}
    func fireAutofillInOtherAppsEnabled(_ enabled: Bool) {}
    func fireImpressionCount(_ count: Int) {}
    func fireDaysToConversion(_ days: Int) {}
}
