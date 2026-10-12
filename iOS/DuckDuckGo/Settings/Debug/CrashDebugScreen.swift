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

    @State private var forcedOnboarding: CrashCollectionOnboarding?

    var body: some View {
        List {
            Section {
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

                SettingsCellView(label: "System Exception", action: {
                    NSException(name: NSExceptionName(rawValue: "TestException"), reason: "Test", userInfo: nil).raise()
                }, isButton: true)

                SettingsCellView(label: "Fatal Error (Background Thread)", action: {
                    Task.detached {
                        fatalError(#function)
                    }
                }, isButton: true)
            }

            SettingsCellView(label: "Reset Crash Send Logs", action: {
                AppUserDefaults().crashCollectionOptInStatus = .undetermined
                ActionMessageView.present(message: "Crash Send logs reset")
            }, isButton: true)

            SettingsCellView(label: "Force Crash Onboarding", action: {
                forceCrashOnboarding()
            }, isButton: true)

        }.navigationTitle("Crashes")
    }

    private func forceCrashOnboarding() {
        let settings = AppUserDefaults()
        settings.crashCollectionOptInStatus = .undetermined

        let onboarding = CrashCollectionOnboarding(appSettings: settings)
        forcedOnboarding = onboarding

        let stub = """
        {"crashDiagnostics":[{"diagnosticMetaData":{"appVersion":"DEBUG","exceptionType":1,"exceptionCode":1,"signal":11,"objectiveCexceptionReason":{"composedMessage":"Simulator forced onboarding","stackTrace":["0 test"]}},"callStackTree":{"callStacks":[],"callStackPerThread":true}}],"timeStampBegin":"2026-01-01 12:00:00","timeStampEnd":"2026-01-01 12:00:00"}
        """

        guard let payload = stub.data(using: .utf8),
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController else {
            forcedOnboarding = nil
            return
        }

        let presenter = root.presentedViewController ?? root
        onboarding.presentOnboardingIfNeeded(for: [payload], from: presenter, sendReport: {
            print("[CrashDebug] sendReport invoked")
        })
    }

}
