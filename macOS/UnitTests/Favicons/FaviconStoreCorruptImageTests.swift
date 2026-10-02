//
//  FaviconStoreCorruptImageTests.swift
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

import CoreData
import Persistence
import SharedTestUtilities
import Utilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Regression tests for #5359 (APPLE-MACOS-B8H): a corrupt stored favicon bitmap makes AppKit raise
/// an Objective-C `NSInvalidUnarchiveOperationException` while Core Data unarchives `imageEncrypted`.
/// `FaviconStore` wraps that access in `NSException.catch`; reverting the fix lets the ObjC exception
/// propagate and **crashes the test process** (that is the fail-on-revert signal).
///
/// The harness registers a stand-in `NSImageTransformer` whose reverse transform raises the same
/// exception a corrupt bitmap would, so the real `FaviconStore` Core Data read path is exercised.
@MainActor
final class FaviconStoreCorruptImageTests: XCTestCase {

    private var database: CoreDataDatabase!
    private var location: URL!
    private var context: NSManagedObjectContext!
    private var registeredTransformerNames: [NSValueTransformerName] = []
    private let imageTransformerName = NSValueTransformerName("NSImageTransformer")

    override func setUp() {
        super.setUp()
        // Register the raising image transformer first. `registerValueTransformers` skips names that
        // are already registered, so this stays in place while the URL/String transformers load.
        ValueTransformer.setValueTransformer(CorruptImageValueTransformer(), forName: imageTransformerName)

        let model = CoreDataDatabase.loadModel(from: Bundle(for: AppDelegate.self), named: "Favicons")!
        registeredTransformerNames = (try? model.registerValueTransformers(keyStore: EncryptionKeyStoreMock())) ?? []
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        database = CoreDataDatabase(name: "FaviconsCorruptImageTest", containerLocation: location, model: model)
        database.loadStore { _, error in
            if let error { XCTFail("Could not load store: \(error.localizedDescription)") }
        }
        context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
    }

    override func tearDown() {
        ValueTransformer.setValueTransformer(nil, forName: imageTransformerName)
        registeredTransformerNames.forEach { ValueTransformer.setValueTransformer(nil, forName: $0) }
        registeredTransformerNames = []
        try? FileManager.default.removeItem(at: location)
        context = nil
        database = nil
        location = nil
        super.tearDown()
    }

    @discardableResult
    private func insertCorruptFavicon() throws -> UUID {
        let identifier = UUID()
        let mo = NSEntityDescription.insertNewObject(forEntityName: FaviconManagedObject.className(), into: context) as! FaviconManagedObject
        mo.identifier = identifier
        mo.imageEncrypted = NSImage()
        mo.urlEncrypted = URL(string: "https://example.com/favicon.ico")! as NSURL
        mo.documentUrlEncrypted = URL(string: "https://example.com/")! as NSURL
        mo.dateCreated = Date()
        mo.relation = Int64(Favicon.Relation.favicon.rawValue)
        try context.save()
        return identifier
    }

    func testLoadFaviconsReturnsFaviconWithNilImageOnCorruptStoredImage() async throws {
        try insertCorruptFavicon()
        let store = FaviconStore(context: context)

        let favicons = try await store.loadFavicons()

        XCTAssertEqual(favicons.count, 1, "The favicon should still load; only its image is dropped")
        XCTAssertNil(favicons.first?.image, "A corrupt stored bitmap must decode to a nil image, not crash")
    }
}

/// Stand-in for the favicon image transformer whose reverse transform raises the Objective-C
/// exception AppKit throws for a corrupt bitmap. `transformedValue` returns placeholder data so
/// inserting the managed object succeeds.
private final class CorruptImageValueTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass { NSData.self }
    override class func allowsReverseTransformation() -> Bool { true }

    override func transformedValue(_ value: Any?) -> Any? {
        Data([0x00])
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        NSException(name: NSExceptionName("NSInvalidUnarchiveOperationException"),
                    reason: "corrupt favicon bitmap (test)",
                    userInfo: nil).raise()
        return nil
    }
}
