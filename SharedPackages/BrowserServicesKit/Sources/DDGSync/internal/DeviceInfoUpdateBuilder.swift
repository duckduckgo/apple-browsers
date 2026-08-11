//
//  DeviceInfoUpdateBuilder.swift
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

import Foundation

struct DeviceInfoUpdateBuilder {

    let crypter: CryptingInternal
    let deviceInfoCodec: DeviceInfoCoding

    func makeUpdate(deviceID: String,
                    deviceName: String,
                    deviceType: String,
                    primaryKey: Data,
                    protectedKey: ProtectedKey) throws -> UpdateDevices.Update {
        let encryptedDeviceInfo = try deviceInfoCodec.encrypt(
            DeviceInfo(name: deviceName, type: deviceType),
            using: protectedKey)
        guard encryptedDeviceInfo.utf8.count <= DeviceInfo.maximumEncryptedLength else {
            throw DeviceInfoMigrationError.encryptedDeviceInfoTooLarge
        }

        return UpdateDevices.Update(
            id: deviceID,
            name: try crypter.encryptAndBase64Encode(deviceName, using: primaryKey),
            type: try crypter.encryptAndBase64Encode(deviceType, using: primaryKey),
            info: encryptedDeviceInfo)
    }
}
