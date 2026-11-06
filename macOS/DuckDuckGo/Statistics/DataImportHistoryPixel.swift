//
//  DataImportHistoryPixel.swift
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

import PixelKit

/**
 * Tells us when a browser stops storing history where the importer looks for it,
 * e.g. Chrome renaming its `History` database.
 *
 * See macOS/PixelDefinitions/pixels/definitions/data_import_history_pixels.json5 for more details.
 */
enum DataImportHistoryPixel: PixelKit.Event {
    var namePrefix: PixelKitNamePrefix { .none }

    case sourceFileMissing(source: String, sourceVersion: String?)

    var name: String {
        switch self {
        case .sourceFileMissing: return "dataimport_history_source-file-missing_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .sourceFileMissing(let source, let sourceVersion):
            var parameters = [Constants.sourceParameter: source]
            parameters[PixelKit.Parameters.sourceBrowserVersion] = sourceVersion
            return parameters
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .sourceFileMissing:
            return [.pixelSource]
        }
    }

    private enum Constants {
        static let sourceParameter = "source"
    }
}
