//
//  DataImportHubPixelContext.swift
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

import Core

enum DataImportHubPixelConstants {
    static let unknownSource = "unknown"
}

struct DataImportHubPixelContext {
    private let entryPoint: String?
    private let source: String?

    init(entryPoint: DataImportViewModel.ImportScreen, source: String?) {
        self.entryPoint = entryPoint.importHubEntryPoint
        self.source = source
    }

    var parameters: [String: String] {
        var parameters = [String: String]()

        if let entryPoint {
            parameters[PixelParameters.entryPoint] = entryPoint
        }

        if let source {
            parameters[PixelParameters.source] = source
        }

        return parameters
    }
}

extension DataImportViewModel.ImportScreen {
    var importHubEntryPoint: String? {
        rawValue
    }

    var importHubEntryPointParameters: [String: String] {
        guard let entryPoint = importHubEntryPoint else {
            return [:]
        }

        return [PixelParameters.entryPoint: entryPoint]
    }
}
