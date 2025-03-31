//
//  ModelAccessHelper.swift
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
import Foundation

public class ModelAccessHelper {

    public static func compileModel(from bundle: Bundle, named name: String) {
        let momdUrl = bundle.url(forResource: name, withExtension: "momd") ??
        bundle.resourceURL!.appendingPathComponent(name + ".momd")
#if DEBUG && os(macOS)
        // when running tests using `swift test` xcdatamodeld is not compiled to momd for some reason
        // this is a workaround to compile it in runtime
        if !FileManager.default.fileExists(atPath: momdUrl.path),
           let xcDataModelUrl = bundle.url(forResource: name, withExtension: "xcdatamodeld"),
           let sdkRoot = ProcessInfo().environment["SDKROOT"],
           let developerDir = sdkRoot.range(of: "/Contents/Developer").map({ sdkRoot[..<$0.upperBound] }) {

            let compileDataModel = Process()
            let momc = "\(developerDir)/usr/bin/momc"
            compileDataModel.executableURL = URL(fileURLWithPath: momc)
            compileDataModel.arguments = [xcDataModelUrl.path, momdUrl.path]
            try? compileDataModel.run()
            compileDataModel.waitUntilExit()
        }
#endif
    }

}
