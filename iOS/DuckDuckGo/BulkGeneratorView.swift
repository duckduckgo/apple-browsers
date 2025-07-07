//
//  BulkGeneratorView.swift
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
import SwiftUI

struct BulkGeneratorView: View {
    
    protocol Factory<T> {

        associatedtype T
        
        var description: String { get }
        var footer: String? { get }
        var options: [String: [String]] { get }

        func starting() async
        
        @discardableResult
        func generate(optionValues: [String: String]) async -> T
        
        func finished() async
        
    }
    
    @State var values: [String: String]
    @State var isBusy = false
    
    let factory: any Factory
    
    func generate() {
        Task { @MainActor in
            isBusy = true
            
            await factory.starting()
            await factory.generate(optionValues: values)
            await factory.finished()

            isBusy = false
        }
    }
    
    init(factory: any Factory) {
        self.factory = factory
        values = self.factory.options.mapValues { $0.first ?? "" }
    }
    
    var body: some View {
        List {
            Section {
                ForEach(factory.options.keys.sorted(), id: \.self) { optionName in
                    Picker(selection: Binding(get: {
                        values[optionName]
                    }, set: {
                        values[optionName] = $0
                    })) {
                        ForEach(factory.options[optionName]!, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    } label: {
                        Text(optionName)
                    }
                    .disabled(isBusy)
                }
            } header: {
                Text(verbatim: "Options")
            } footer: {
                VStack {
                    Text(factory.footer ?? "")

                    if isBusy {
                        SwiftUI.ProgressView()
                    }
                }
            }
        }
        .navigationTitle(factory.description)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    generate()
                } label: {
                    Text(verbatim: "Generate")
                }
                .disabled(isBusy)
            }
        }
    }
}

struct BulkTabFactory: BulkGeneratorView.Factory {

   let description: String = "Bulk Tab Generation"
    var footer: String? {
        "%d tabs. Restart app after generation".format(arguments: tabManager.count)
    }
    let options = ["Tab Count": [ "100", "500", "1000", "5000", "10000"]]

    let urlFactory: any BulkGeneratorView.Factory<URL>
    
    let tabManager: TabManager
    
    init(tabManager: TabManager, urlFactory: any BulkGeneratorView.Factory<URL> = BulkURLFactory()) {
        self.tabManager = tabManager
        self.urlFactory = urlFactory
    }
    
    func starting() {
        // no-op
    }
    
    func generate(optionValues: [String: String]) async {
        let count = Int(optionValues["Tab Count"] ?? "0") ?? 0
        for index in 0 ..< count {
            let url = await urlFactory.generate(optionValues: ["index": "\(index)"])
            let tab = Tab(uid: UUID().uuidString, link: .init(title: "Generated Tab \(index)", url: url))
            tabManager.model.add(tab: tab)
        }
        return
    }
    
    func finished() {
        tabManager.save()
    }
    
}

struct BulkURLFactory: BulkGeneratorView.Factory {
    
    static let baseURLs = [
        "https://example.com/page",
        "https://robohash.org/page",
        "https://loremflickr.com/200/200/page",
        "https://dummyimage.com/100/100/fff?text=page",
        "https://api.dicebear.com/9.x/adventurer/svg?seed=page",
    ]
    
    let description: String = "Bulk URL Generation"
    let footer: String? = nil
    let options: [String: [String]] = [
        "index": ["any valid int"]
    ]

    func starting() {
        // no-op
    }
    
    func generate(optionValues: [String: String]) async -> URL {
        let index = Int(optionValues["index"] ?? "0") ?? 0
        return URL(string: Self.baseURLs.randomElement()! + "\(index)")!
    }
    
    func finished() {
        // no-op
    }
    
}
