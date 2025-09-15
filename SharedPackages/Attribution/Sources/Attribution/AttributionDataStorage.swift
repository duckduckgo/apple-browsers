//
//  AttributionDataStorage.swift
//  Attribution
//
//  Created by Federico Cappelli on 15/09/2025.
//

import Foundation

public protocol AttributionDataStoring {

    var appStarts: AppStarts? { get }
}

class AttributionDataStorage: AttributionDataStoring {

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    enum StorageKey: String {
        /// Array of app start timestamps
        case startTimeStamps
    }

    func encode(_ object: Codable, to userDefaults: UserDefaults, key: StorageKey) {
        guard let data = try? JSONEncoder().encode(object) else { return }
        userDefaults.set(data, forKey: key.rawValue)
    }

    func decode<T: Codable>(from userDefaults: UserDefaults, key: StorageKey) -> T? {
        guard let data = userDefaults.data(forKey: key.rawValue),
              let object = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return object
    }

    // MARK: - Direct access

    var appStarts: AppStarts? {
        set { encode(newValue, to: userDefaults, key: .startTimeStamps) }
        get { return decode(from: userDefaults, key: .startTimeStamps) }
    }
}
