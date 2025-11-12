//
//  DataAuditDebugScreen.swift
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

struct DataAuditDebugScreen: View {

    @ObservedObject var model = DataAuditModel()

    var body: some View {
        list()
    }

    @ViewBuilder func list() -> some View {
        List {
            Section("Actions") {
                Button("Scan") {
                    model.scan()
                }
            }

            if !model.results.isEmpty {
                Section("Results") {
                    ForEach(model.results) { result in
                        NavigationLink(destination: LazyView(ResultDetail(result: result))) {
                            Text(result.title)
                        }
                    }
                }
            }
        }
    }

    struct ResultDetail: View {

        let result: DataAuditModel.Result

        var body: some View {
            ScrollView {
                Text(result.details)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
            }
            .navigationTitle(result.title)
        }

    }

}

class DataAuditModel: ObservableObject {

    struct Result: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let details: String
    }

    @Published var results = [Result]()

    func scan() {
        Task { @MainActor in

            do {
                results.append(.init(title: "Caches", details: try await scanCachesDirectory()))
            } catch {
                results.append(.init(title: "❌ Caches", details: error.localizedDescription))
            }

        }
    }

    func scanCachesDirectory() async throws -> String {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.path + "\n" + (try listContentsOf(caches, level: 0))
    }

    func listContentsOf(_ dir: URL, level: Int) throws -> String {
        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isHiddenKey])
        let indent = String(repeatElement("*", count: level + 1))
        var result = ""
        for item in contents {
            let path = item.absoluteString.dropping(prefix: dir.absoluteString)
            result += indent + " " + path + "\n"

            var isDir = ObjCBool(false)
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)

            if isDir.boolValue {
                result += try listContentsOf(item, level: level + 1)
            }
        }

        return result
    }

}
