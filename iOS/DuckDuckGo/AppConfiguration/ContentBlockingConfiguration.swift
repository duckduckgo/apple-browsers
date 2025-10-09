//
//  ContentBlockingConfiguration.swift
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
import Core
import Persistence

final class ContentBlockingConfiguration {
    
    private let application: UIApplication
    private let keyValueStore: ThrowingKeyValueStoring

    init(application: UIApplication = UIApplication.shared, keyValueStore: ThrowingKeyValueStoring) {
        self.application = application
        self.keyValueStore = keyValueStore
    }

    func prepareContentBlocking() {
        ContentBlocking.shared.onCriticalError = {
            // Set marker for compilation failure
            try? self.keyValueStore.set(Date(), forKey: "contentBlockingCompilationFailureDate")

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                fatalError()
            }
        }
        
        // Explicitly prepare ContentBlockingUpdating instance before Tabs are created
        _ = ContentBlockingUpdating.shared
    }

}
