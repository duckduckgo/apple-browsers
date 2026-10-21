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

    private func removeTestFiles() {
        // Remove all test files created by this test class
        let fileManager = FileManager.default
        let testFiles = [
            "FileStoreTest_StoringDataWithoutEncryption",
            "FileStoreTest_ReadingNonExistentData",
            "FileStoreTest_ReadingDataWithoutEncryption",
            "FileStoreTest_StoringAndRetrievingEncryptedData",
            "FileStoreTest_LoadDataFromEncryptedStoreDecryptsByDefault",
            "FileStoreTest_LoadDataWithoutDecryptionReturnsEncryptedData",
            "FileStoreTest_OverwritingStoredFiles",
            "FileStoreTest_CheckingFilePresence",
            "FileStoreTest_PersistenceLocation"
        ]

        for fileName in testFiles {
            try? fileManager.removeItem(at: URL.persistenceLocation(for: fileName))
        }
    }

    @Test("Data can be stored without encryption")
    func testStoringDataWithoutEncryption() {
        let testFileLocation = getTestFileLocation(for: "StoringDataWithoutEncryption")
        let store = EncryptedFileStore()
        let success = store.persist(testData, url: testFileLocation)

        #expect(success == true)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @Test("Reading non-existent data returns nil")
    func testReadingNonExistentData() {
        let testFileLocation = getTestFileLocation(for: "ReadingNonExistentData")
        let store = EncryptedFileStore()
        let data = store.loadData(at: testFileLocation)

        #expect(data == nil)
    }

    @Test("Data can be read without encryption")
    func testReadingDataWithoutEncryption() {
        let testFileLocation = getTestFileLocation(for: "ReadingDataWithoutEncryption")
        let store = EncryptedFileStore()

        _ = store.persist(testData, url: testFileLocation)
        let readData = store.loadData(at: testFileLocation)

        #expect(testData == readData)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @Test("Data can be stored and retrieved with encryption")
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

    @Test("LoadData from encrypted store decrypts by default")
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

    @Test("LoadData without decryption returns encrypted data")
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

    @Test("Stored files can be overwritten")
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

    @Test("File presence can be checked")
    func testCheckingFilePresence() {
        let testFileLocation = getTestFileLocation(for: "CheckingFilePresence")
        let store = EncryptedFileStore()

        let data = "Hello, World".data(using: .utf8)!
        #expect(store.persist(data, url: testFileLocation) == true)
        #expect(store.hasData(at: testFileLocation) == true)
        try? FileManager.default.removeItem(at: testFileLocation)
    }

    @Test("Persistence location is correctly constructed")
    func testPersistenceLocation() {
        let fileName = "FileStoreTest_PersistenceLocation"
        let location = URL.persistenceLocation(for: fileName)
        let components = location.pathComponents

        #expect(components.last! == fileName)
    }
}
