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
import Core

struct DataAuditDebugScreen: View {

    @ObservedObject var model = DataAuditModel()

    var body: some View {
        list()
    }

    @ViewBuilder func list() -> some View {
        List {
            Section {
                Button {
                    model.scan()
                } label: {
                    Text(verbatim: "Scan")
                }

                if !model.results.isEmpty {
                    Button {
                        model.copy()
                    } label: {
                        Text(verbatim: "Copy")
                    }
                }
            } header: {
                Text(verbatim: "Actions")
            }

            if !model.results.isEmpty {
                Section {
                    ForEach(model.results) { result in
                        NavigationLink(destination: LazyView(ResultDetail(result: result))) {
                            Text(result.title)
                        }
                    }
                } header: {
                    Text(verbatim: "Results")
                }
            }
        }
    }

    struct ResultDetail: View {

        let result: DataAuditModel.Result

        var body: some View {
            TextEditor(text: Binding<String>(get: {
                result.details
            }, set: { _ in
                // not supported
            }
            ))
            .navigationTitle(result.title)
        }

    }

}

class DataAuditModel: ObservableObject {

    enum ScanError: Error {

        case general(_ message: String)

    }

    struct Result: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let details: String
    }

    @Published var results = [Result]()

    func copy() {
        var md = "# Data Audit Scan \(Date())\n\n"

        results.forEach {
            md += "\n## " + $0.title + "\n"
            md += $0.details
        }

        UIPasteboard.general.string = md
    }

    func scan() {
        Task { @MainActor in
            results.removeAll()

            do {
                results.append(.init(title: "Caches", details: try await scanDirectory(.cachesDirectory)))
            } catch {
                results.append(.init(title: "❌ Caches", details: error.localizedDescription))
            }

            do {
                results.append(.init(title: "Documents", details: try await scanDirectory(.documentDirectory)))
            } catch {
                results.append(.init(title: "❌ Documents", details: error.localizedDescription))
            }

            do {
                results.append(.init(title: "Container (Bookmarks)", details: try await scanContainerDirectory(suffix: "bookmarks")))
            } catch {
                results.append(.init(title: "❌ Container (Bookmarks)", details: error.localizedDescription))
            }

            do {
                results.append(.init(title: "Container (Database)", details: try await scanContainerDirectory(suffix: "database")))
            } catch {
                results.append(.init(title: "❌ Container (Database)", details: error.localizedDescription))
            }

            do {
                results.append(.init(title: "Container (ContentBlocker)", details: try await scanContainerDirectory(suffix: "contentblocker")))
            } catch {
                results.append(.init(title: "❌ Container (ContentBlocker)", details: error.localizedDescription))
            }

            do {
                results.append(.init(title: "Container (Statistics)", details: try await scanContainerDirectory(suffix: "statistics")))
            } catch {
                results.append(.init(title: "❌ Container (Statistics)", details: error.localizedDescription))
            }

            do {
                results.append(.init(title: "Container (Netp)", details: try await scanContainerDirectory(suffix: "netp")))
            } catch {
                results.append(.init(title: "❌ Container (Netp)", details: error.localizedDescription))
            }

            do {
                results.append(.init(title: "Container (App Configuration)", details: try await scanContainerDirectory(suffix: "app-configuration")))
            } catch {
                results.append(.init(title: "❌ Container (App Configuration)", details: error.localizedDescription))
            }

        }
    }

    func scanContainerDirectory(suffix: String) async throws -> String {
        let groupID = "\(Global.groupIdPrefix).\(suffix)"
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw ScanError.general("No URL for group ID \(groupID)")
        }
        return dir.path + "\n" + (try listContentsOf(dir, level: 0))
    }

    func scanDirectory(_ dir: FileManager.SearchPathDirectory) async throws -> String {
        let dir = FileManager.default.urls(for: dir, in: .userDomainMask)[0]
        return dir.path + "\n" + (try listContentsOf(dir, level: 0))
    }

    func listContentsOf(_ dir: URL, level: Int) throws -> String {
        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isHiddenKey])
        let indent = String(repeatElement(" ", count: level * 4)) + "*"
        var result = ""
        for item in contents {
            var isDir = ObjCBool(false)
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)

            let path = item.absoluteString.dropping(prefix: dir.absoluteString)

            if isDir.boolValue {
                result += indent + " " + path + "\n"
                result += try listContentsOf(item, level: level + 1)
            } else {
                let size = item.fileSize
                result += indent + " " + path + " (" + fileSize(size) + ")\n"
            }
        }

        return result
    }

    func fileSize(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = .useAll
        f.countStyle = .file
        f.includesUnit = true
        f.includesCount = true
        return f.string(fromByteCount: Int64(bytes))
    }

}
