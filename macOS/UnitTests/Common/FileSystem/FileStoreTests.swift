//
//  FileStoreTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import CryptoKit
import SharedTestUtilities
import Testing
import Utilities

@testable import DuckDuckGo_Privacy_Browser

final class FileStoreTests {
    private let testData = "Hello, World".data(using: .utf8)!

    private func getTestFileLocation(for testName: String) -> URL {
        return URL.persistenceLocation(for: "FileStoreTest_\(testName)")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Data can be stored without encryption", .timeLimit(.minutes(1)))
    func testStoringDataWithoutEncryption() {
        let testFileLocation = getTestFileLocation(for: "StoringDataWithoutEncryption")
        let store = EncryptedFileStore()
        let success = store.persist(testData, url: testFileLocation)

        #expect(success == true)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reading non-existent data returns nil", .timeLimit(.minutes(1)))
    func testReadingNonExistentData() {
        let testFileLocation = getTestFileLocation(for: "ReadingNonExistentData")
        let store = EncryptedFileStore()
        let data = store.loadData(at: testFileLocation)

        #expect(data == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Data can be read without encryption", .timeLimit(.minutes(1)))
    func testReadingDataWithoutEncryption() {
        let testFileLocation = getTestFileLocation(for: "ReadingDataWithoutEncryption")
        let store = EncryptedFileStore()

        _ = store.persist(testData, url: testFileLocation)
        let readData = store.loadData(at: testFileLocation)

        #expect(testData == readData)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Data can be stored and retrieved with encryption", .timeLimit(.minutes(1)))
    func testStoringAndRetrievingEncryptedData() throws {
        let testFileLocation = getTestFileLocation(for: "StoringAndRetrievingEncryptedData")
        let keyStore = MockEncryptionKeyStore(generator: EncryptionKeyGenerator(), account: "mock-account")
        let key = try keyStore.readKey()
        let encryptedStore = EncryptedFileStore(encryptionKey: key)

        #expect(encryptedStore.persist(testData, url: testFileLocation) == true)

        // A new key should have been generated in the key store.
        #expect(keyStore.storedKeys.count == 1)

        // Verify that there is data at the location that was written to.
        #expect(encryptedStore.hasData(at: testFileLocation) == true)

        // Data should come back decrypted, so it should be equal to the original test data.
        let data = encryptedStore.loadData(at: testFileLocation)
        #expect(data == testData)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @available(iOS 16, macOS 13, *)
    @Test("LoadData from encrypted store decrypts by default", .timeLimit(.minutes(1)))
    func testThatLoadDataFromEncryptedStoreDecryptsByDefault() throws {
        let testFileLocation = getTestFileLocation(for: "LoadDataFromEncryptedStoreDecryptsByDefault")
        let keyStore = MockEncryptionKeyStore(generator: EncryptionKeyGenerator(), account: "mock-account")
        let key = try keyStore.readKey()
        let encryptedStore = EncryptedFileStore(encryptionKey: key)

        _ = encryptedStore.persist(testData, url: testFileLocation)
        let readData = try #require(encryptedStore.loadData(at: testFileLocation), "Failed to load data")
        #expect(testData == readData)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @available(iOS 16, macOS 13, *)
    @Test("LoadData without decryption returns encrypted data", .timeLimit(.minutes(1)))
    func testWhenLoadDataIsCalledWithoutDecryptionThenDataIsNotDecrypted() throws {
        let testFileLocation = getTestFileLocation(for: "LoadDataWithoutDecryptionReturnsEncryptedData")
        let keyStore = MockEncryptionKeyStore(generator: EncryptionKeyGenerator(), account: "mock-account")
        let key = try keyStore.readKey()
        let encryptedStore = EncryptedFileStore(encryptionKey: key)

        _ = encryptedStore.persist(testData, url: testFileLocation)
        let readData = try #require(encryptedStore.loadData(at: testFileLocation, decryptIfNeeded: false), "Failed to load encrypted data")
        #expect(testData != readData)
        #expect(encryptedStore.decrypt(readData) == testData)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Stored files can be overwritten", .timeLimit(.minutes(1)))
    func testOverwritingStoredFiles() throws {
        let testFileLocation = getTestFileLocation(for: "OverwritingStoredFiles")
        let keyStore = MockEncryptionKeyStore(generator: EncryptionKeyGenerator(), account: "mock-account")
        let key = try keyStore.readKey()
        let encryptedStore = EncryptedFileStore(encryptionKey: key)

        #expect(encryptedStore.persist("First Write".data(using: .utf8)!, url: testFileLocation) == true)
        #expect(encryptedStore.persist("Second Write".data(using: .utf8)!, url: testFileLocation) == true)
        #expect(encryptedStore.persist("Third Write".data(using: .utf8)!, url: testFileLocation) == true)

        let data = encryptedStore.loadData(at: testFileLocation)
        #expect("Third Write".data(using: .utf8) == data)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @available(iOS 16, macOS 13, *)
    @Test("File presence can be checked", .timeLimit(.minutes(1)))
    func testCheckingFilePresence() {
        let testFileLocation = getTestFileLocation(for: "CheckingFilePresence")
        let store = EncryptedFileStore()

        let data = "Hello, World".data(using: .utf8)!
        #expect(store.persist(data, url: testFileLocation) == true)
        #expect(store.hasData(at: testFileLocation) == true)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Persistence location is correctly constructed", .timeLimit(.minutes(1)))
    func testPersistenceLocation() {
        let fileName = "FileStoreTest_PersistenceLocation"
        let location = URL.persistenceLocation(for: fileName)
        let components = location.pathComponents

        #expect(components.last! == fileName)
    }
}
