//
//  CrashDebugScreen.swift
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

import SwiftUI
import Crashes

struct CrashDebugScreen: View {

    var body: some View {
        List {
            SettingsCellView(label: "Fatal Error", action: {
                fatalError(#function)
            }, isButton: true)

            SettingsCellView(label: "Memory", action: {
                var array = [String]()
                while 1 != 2 {
                    array.append(array.joined())
                }
            }, isButton: true)
            SettingsCellView(label: "div/0 error", action: {
                func zero() -> Int { return 0 }
                print(10 / zero())
            }, isButton: true)
            SettingsCellView(label: "CPP Exception", action: {
                throwTestCppException()
            }, isButton: true)
        }.navigationTitle("Crash")
    }

}
