//
//  ExperimentsDataStore.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public protocol ExperimentsDataStoring {
    var experiments: Experiments? { get set }
}

public protocol LocalDataStoring {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

public struct ExperimentsDataStore: ExperimentsDataStoring {

    private enum Constants {
        static let experimentsDataKey = "ExperimentsData"
    }
    private let localDataStoring: LocalDataStoring
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(localDataStoring: LocalDataStoring = UserDefaults.standard) {
        self.localDataStoring = localDataStoring
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    public var experiments: Experiments? {
        get {
            guard let savedData = localDataStoring.data(forKey: Constants.experimentsDataKey) else { return nil }
            return try? decoder.decode(Experiments.self, from: savedData)
        }
        set {
            if let encodedData = try? encoder.encode(newValue) {
                localDataStoring.set(encodedData, forKey: Constants.experimentsDataKey)
            }
        }
    }
}

extension UserDefaults: LocalDataStoring {}
