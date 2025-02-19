//
//  DataImportReportModel.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Common
import Foundation
import BrowserServicesKit

struct DataImportReportModel {

    var osVersion: String = "\(ProcessInfo.processInfo.operatingSystemVersion)"
    var appVersion: String = "\(AppVersion.shared.versionNumber)"

    var importSource: DataImport.Source
    var importSourceVersion: String?

    var importSourceDescription: String {
        [importSource.importSourceName, importSourceVersion].compactMap { $0 }.joined(separator: " ")
    }

    var error: LocalizedError

    var text: String = ""

    var retryNumber: Int

}
