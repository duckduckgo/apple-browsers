//
//  MappingValidatorTests.swift
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

import Testing
@testable import RemoteMessaging

struct TestModel {
    let id: String
    let name: String?
    let items: [String]
    let optionalItems: [String]?
    let status: String
}

enum TestStatus: String {
    case active
    case inactive
}

// MARK: - MappingError Tests

@Suite("Mapping Validator Tests")
struct MappingValidatorTests { }

extension MappingValidatorTests {

    struct ErrorMessages {

        @Test("Check Error Description For Nil Value Is Correct")
        func checkNilValueErrorDescription() {
            // GIVEN
            let keyPath = \TestModel.name
            let expectedLocalizedError = "Found nil value for \(String(describing: keyPath))"

            // WHEN
            let error = MappingError.nilValue(keyPath)

            // THEN
            #expect(error.localizedDescription == expectedLocalizedError)
        }

        @Test("Check Error Description For Empty Value Is Correct")
        func checkEmptyValueErrorDescription() {
            // GIVEN
            let keyPath = \TestModel.items
            let expectedLocalizedError = "Found empty value for \(String(describing: keyPath))"

            // WHEN
            let error = MappingError.emptyValue(keyPath)

            // THEN
            #expect(error.localizedDescription == expectedLocalizedError)
        }

        @Test("Check Error Description For Duplicate Value Is Correct")
        func checkDuplicateValueErrorDescription() {
            // GIVEN
            let keyPath = \TestModel.id
            let expectedLocalizedError = "Found duplicate value for \(String(describing: keyPath))"

            // WHEN
            let error = MappingError.duplicateValue(keyPath)

            // THEN
            #expect(error.localizedDescription == expectedLocalizedError)
        }

        @Test("Check Error Description For Invalid Value Is Correct")
        func checkInvalidValueErrorDescription() {
            // GIVEN
            let keyPath = \TestModel.status
            let expectedLocalizedError = "Found invalid value for \(String(describing: keyPath))"

            // WHEN
            let error = MappingError.invalidValue(keyPath)

            // THEN
            #expect(error.localizedDescription == expectedLocalizedError)
        }
    }

}

extension MappingValidatorTests {

    @Suite("Not Empty")
    struct NotEmptyTests {

        @Test("Check Non-empty Collection Passes Validation")
        func checkNonEmptyCollectionPassesValidation() throws {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: ["a", "b"], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // WHEN
            let result = try sut.notEmpty(\.items)

            // THEN

            #expect(result == ["a", "b"])
        }

        @Test("Empty Collection Throws EmptyValue error")
        func checkEmptyCollectionThrowsEmptyError() {
            // GIVEN
            let model = TestModel(id: "", name: "Test", items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.emptyValue(\TestModel.items)) {
                // WHEN
                try sut.notEmpty(\.items)
            }
        }

        @Test("Check Empty String Throws EmptyValue Error")
        func checkEmptyStringThrowsEmptyError() {
            // GIVEN
            let model = TestModel(id: "", name: "Test", items: ["a"], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.emptyValue(\TestModel.id)) {
                // WHEN
                try sut.notEmpty(\.id)
            }
        }

        @Test("Check Non-empty String Passes Validation")
        func checkNonEmptyStringPasses() throws {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: ["a"], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // WHEN
            let result = try sut.notEmpty(\.id)

            // THEN
            #expect(result == "123")
        }

        @Test("Check Non-empty Collection With Explicit KeyPath Passes Validation")
        func checkExplicitKeyPathPassesValidation() throws {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: ["a"], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)
            let items = ["x", "y"]

            // WHEN
            let result = try sut.notEmpty(items, keyPath: \TestModel.items)

            // THEN
            #expect(result == ["x", "y"])
        }

        @Test("Check Empty Collection With Explicit KeyPath Throws EmptyValue Error")
        func checkExplicitKeyPathThrowsOnEmpty() {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: ["a"], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)
            let emptyItems: [String] = []

            // THEN
            #expect(throws: MappingError.emptyValue(\TestModel.items)) {
                // WHEN
                try sut.notEmpty(emptyItems, keyPath: \TestModel.items)
            }
        }
    }

}

extension MappingValidatorTests {

    @Suite("Not Nil")
    struct NotNilTests {

        @Test("Check Non-nil Value Passes Validation")
        func checkNonNilValuePasses() throws {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // WHEN
            let result = try sut.notNil(\.name)

            // THEN
            #expect(result == "Test")
        }

        @Test("Check Nil Value Throws NilValue Error")
        func checkNilValueThrows() {
            // GIVEN
            let model = TestModel(id: "123", name: nil, items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.nilValue(\TestModel.name)) {
                // WHEN
                try sut.notNil(\.name)
            }
        }

        @Test("Check Non-nil Optional Collection Passes Validation")
        func checkOptionalCollectionPasses() throws {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: ["a"], status: "active")
            let sut = MappingValidator(root: model)

            // WHEN
            let result = try sut.notNil(\.optionalItems)

            // THEN
            #expect(result == ["a"])
        }
    }

}

extension MappingValidatorTests {

    @Suite("Not Nil Or Empty")
    struct NotNilOrEmptyTests {

        @Test("Check Non-nil Non-empty Collection Passes Validation")
        func checkNonNilNonEmptyPasses() throws {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: ["a", "b"], status: "active")
            let sut = MappingValidator(root: model)

            // WHEN
            let result = try sut.notNilOrEmpty(\.optionalItems)

            // THEN
            #expect(result == ["a", "b"])
        }

        @Test("Check Nil Optional Throws NilValue Error")
        func checkNilOptionalThrows() {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.nilValue(\TestModel.optionalItems)) {
                // WHEN
                try sut.notNilOrEmpty(\.optionalItems)
            }
        }

        @Test("Check Empty optional Collection Throws EmptyValue Error")
        func checkEmptyOptionalCollectionThrows() {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: [], status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.emptyValue(\TestModel.optionalItems)) {
                // WHEN
                try sut.notNilOrEmpty(\.optionalItems)
            }
        }

        @Test("Check Non-nil Empty String Throws EmptyValue Error")
        func nonNilEmptyStringThrows() {
            // GIVEN
            let model = TestModel(id: "123", name: "", items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.emptyValue(\TestModel.name)) {
                // WHEN
                try sut.notNilOrEmpty(\.name)
            }
        }
    }

}

extension MappingValidatorTests {

    @Suite("Map Enum")
    struct MapEnumTests {

        @Test("Check Valid Enum Raw Value Maps Successfully")
        func checkValidEnumRawValueMaps() throws {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // WHEN
            let result = try sut.mapEnum(\.status, to: TestStatus.self)

            // THEN
            #expect(result == .active)
        }

        @Test("Check Invalid Enum Raw Value Throws InvalidValue Error")
        func checkInvalidEnumRawValueThrows() {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: nil, status: "unknown")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.invalidValue(\TestModel.status)) {
                // WHEN
                try sut.mapEnum(\.status, to: TestStatus.self)
            }
        }

        @Test("Check Valid Enum Values Map Correctly", arguments: zip(["active", "inactive"], [TestStatus.active, .inactive]))
        func checkDifferentValidEnumValues(rawStatus: String, expectedStatus: TestStatus) throws {
            // GIVEN
            let model = TestModel(id: "1", name: "Test", items: [], optionalItems: nil, status: rawStatus)
            let sut = MappingValidator(root: model)

            // WHEN
            let result = try sut.mapEnum(\.status, to: TestStatus.self)

            // THEN
            #expect(result == expectedStatus)
        }
    }

}

extension MappingValidatorTests {

    @Suite("Map Required")
    struct MapRequiredTests {

        @Test("Check Valid Transformation Returns Result")
        func checkValidTransformationReturns() throws {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // WHEN
            let result = try sut.mapRequired(\.name) { name throws(MappingError) -> String in
                // Simulate validation throwing function
                let id = try sut.notEmpty(\.id)
                return id + " " + name.uppercased()
            }

            // THEN
            #expect(result == "123 TEST")
        }

        @Test("Check Nil Value Throws NilValue Error")
        func checkNilValueThrowsNilError() {
            // GIVEN
            let model = TestModel(id: "123", name: nil, items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.nilValue(\TestModel.name)) {
                // WHEN
                try sut.mapRequired(\.name) { name in
                    return name.uppercased()
                }
            }
        }

        @Test("Check Transform Returning Nil Throws InvalidValue Error")
        func checkTransformReturningNilThrows() {
            // GIVEN
            let model = TestModel(id: "123", name: "Test", items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.invalidValue(\TestModel.name)) {
                // WHEN
                try sut.mapRequired(\.name) { _ throws(MappingError) -> String? in
                    return nil
                }
            }
        }

        @Test("Check Transform Throwing Error Propagates Error")
        func checkTransformWithTypedThrowPropagates() {
            // GIVEN
            let model = TestModel(id: "", name: "Test", items: [], optionalItems: nil, status: "active")
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.emptyValue(\TestModel.id)) {
                // WHEN
                try sut.mapRequired(\.name) { name throws(MappingError) -> String? in
                    // Simulate validation that throws
                    throw MappingError.emptyValue(\TestModel.id)
                }
            }
        }
    }

}

extension MappingValidatorTests {

    @Suite("Model Validation")
    struct ModelValidationTests {

        struct Model {
            let id: String
            let type: String
            let items: [String]?
            let metadata: [String: String]?
        }

        enum ModelType: String {
            case primary
            case secondary
        }

        @Test("Check Model Fields Validation Succeeds")
        func checkModelValidationSucceeds() throws {
            // GIVEN
            let model = Model(
                id: "complex-123",
                type: "primary",
                items: ["item1", "item2"],
                metadata: ["key": "value"]
            )
            let sut = MappingValidator(root: model)

            // WHEN
            let id = try sut.notEmpty(\.id)
            let type = try sut.mapEnum(\.type, to: ModelType.self)
            let items = try sut.notNilOrEmpty(\.items)

            // THEN
            #expect(id == "complex-123")
            #expect(type == .primary)
            #expect(items == ["item1", "item2"])
        }

        @Test("Check Model Validation Fails On First Error")
        func checkModelValidationFailsEarly() {
            // GIVEN
            let model = Model(
                id: "",  // This will fail first
                type: "invalid",
                items: [],
                metadata: nil
            )
            let sut = MappingValidator(root: model)

            // THEN
            #expect(throws: MappingError.emptyValue(\Model.id)) {
                // WHEN
                _ = try sut.notEmpty(\.id)
                _ = try sut.mapEnum(\.type, to: ModelType.self)
                _ = try sut.notNilOrEmpty(\.items)
            }
        }

        @Test("Check Chained Map Required Transformations Succeeds")
        func checkChainedMapRequiredTransformations() throws {
            // GIVEN
            let model = Model(
                id: "123",
                type: "primary",
                items: ["a", "b", "c"],
                metadata: ["count": "3"]
            )
            let sut = MappingValidator(root: model)

            // WHEN
            let transformedItems = try sut.mapRequired(\.items) { items throws(MappingError) -> [String]? in
                let validated = try sut.notEmpty(items, keyPath: \Model.items)
                return validated.map { $0.uppercased() }
            }

            // THEN
            #expect(transformedItems == ["A", "B", "C"])
        }
    }

}
