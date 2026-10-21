//
//  UserDefaultsWrapperTests.swift
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

import Testing
@testable import DuckDuckGo_Privacy_Browser

private extension UserDefaultsWrapperKey {
    static let test = Self(rawValue: "test")
}

final class UserDefaultsWrapperTests {

    // MARK: String

    @Test("String value returns default value when not set")
    func testStringValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: "value", defaults: defaults)
        #expect(wrapper.wrappedValue == "value")
    }

    @Test("String value is updated correctly")
    func testStringValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: "value", defaults: defaults)
        wrapper.wrappedValue = "new"
        #expect(wrapper.wrappedValue == "new")
        #expect((defaults.dictionary as! [String: String]) == ["test": "new"])
    }

    @Test("String value is cleared correctly")
    func testStringValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: "value", defaults: defaults)
        wrapper.wrappedValue = "new"
        wrapper.clear()
        #expect(wrapper.wrappedValue == "value")
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("String value works with shared defaults")
    func testStringValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: "value", defaults: defaults)
        #expect(wrapper.wrappedValue == "value")
        wrapper.wrappedValue = "new"
        #expect(wrapper.wrappedValue == "new")

        UserDefaultsWrapper<String>(key: .test, defaultValue: "value", defaults: defaults).clear()
        #expect(wrapper.wrappedValue == "value")
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: Optional<String>

    @Test("Optional string value returns default value when not set")
    func testOptionalStringValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<String?>(key: .test, defaultValue: "value", defaults: defaults)
        #expect(wrapper.wrappedValue == "value")
    }

    @Test("Optional string value returns nil when no default is set")
    func testOptionalStringValueNilValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<String?>(key: .test, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional string value is updated correctly")
    func testOptionalStringValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<String?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = "new"
        #expect(wrapper.wrappedValue == "new")
        #expect((defaults.dictionary as! [String: String]) == ["test": "new"])
    }

    @Test("Optional string value is removed correctly")
    func testOptionalStringValueRemoval() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<String?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = "new"
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional string value is cleared correctly")
    func testOptionalStringValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<String?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = "new"
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional string value works with shared defaults")
    func testOptionalStringValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<String?>(key: .test, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = "new"
        #expect(wrapper.wrappedValue == "new")

        UserDefaultsWrapper<String?>(key: .test, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: Int

    @Test("Int value returns default value when not set")
    func testIntValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: 42, defaults: defaults)
        #expect(wrapper.wrappedValue == 42)
    }

    @Test("Int value is updated correctly")
    func testIntValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: 42, defaults: defaults)
        wrapper.wrappedValue = 100
        #expect(wrapper.wrappedValue == 100)
        #expect((defaults.dictionary as! [String: Int]) == ["test": 100])
    }

    @Test("Int value is cleared correctly")
    func testIntValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: 42, defaults: defaults)
        wrapper.wrappedValue = 100
        wrapper.clear()
        #expect(wrapper.wrappedValue == 42)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Int value works with shared defaults")
    func testIntValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: 42, defaults: defaults)
        #expect(wrapper.wrappedValue == 42)
        wrapper.wrappedValue = 100
        #expect(wrapper.wrappedValue == 100)

        UserDefaultsWrapper<Int>(key: .test, defaultValue: 42, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == 42)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: Optional<Int>

    @Test("Optional Int value returns default value when not set")
    func testOptionalIntValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .test, defaultValue: 42, defaults: defaults)
        #expect(wrapper.wrappedValue == 42)
    }

    @Test("Optional Int value returns nil when no default is set")
    func testOptionalIntValueNilValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .test, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional Int value is updated correctly")
    func testOptionalIntValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = 100
        #expect(wrapper.wrappedValue == 100)
        #expect((defaults.dictionary as! [String: Int]) == ["test": 100])
    }

    @Test("Optional Int value is removed correctly")
    func testOptionalIntValueRemoval() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = 100
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Int value is cleared correctly")
    func testOptionalIntValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = 100
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Int value works with shared defaults")
    func testOptionalIntValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .test, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = 100
        #expect(wrapper.wrappedValue == 100)

        UserDefaultsWrapper<Int?>(key: .test, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: Optional<Int> with enum Key

    @Test("Optional Int value returns default value when not set with enum key")
    func testOptionalIntValueDefaultValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .lastCrashReportCheckDate, defaultValue: 42, defaults: defaults)
        #expect(wrapper.wrappedValue == 42)
    }

    @Test("Optional Int value returns nil when no default is set with enum key")
    func testOptionalIntValueNilValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional Int value is updated correctly with enum key")
    func testOptionalIntValueUpdatingWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = 100
        #expect(wrapper.wrappedValue == 100)
        #expect((defaults.dictionary as! [String: Int]) == [UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue: 100])
    }

    @Test("Optional Int value is removed correctly with enum key")
    func testOptionalIntValueRemovalWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = 100
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Int value is cleared correctly with enum key")
    func testOptionalIntValueClearWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = 100
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Int value works with shared defaults with enum key")
    func testOptionalIntValueSharedDefaultsWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Int?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = 100
        #expect(wrapper.wrappedValue == 100)

        UserDefaultsWrapper<Int?>(key: .lastCrashReportCheckDate, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue) == nil)
    }

    // MARK: RawRepresentable

    @Test("RawRepresentable value returns default value when not set")
    func testRawRepresentableValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        #expect(wrapper.wrappedValue.rawValue == "value")
    }

    @Test("RawRepresentable value is updated correctly")
    func testRawRepresentableValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "new"))
        #expect((defaults.dictionary as! [String: String]) == ["test": "new"])
    }

    @Test("RawRepresentable value is cleared correctly")
    func testRawRepresentableValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        wrapper.clear()
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("RawRepresentable value works with shared defaults")
    func testRawRepresentableValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "new"))

        UserDefaultsWrapper<MyRawRepresentable>(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults).clear()
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: Optional<RawRepresentable>

    struct MyRawRepresentable: RawRepresentable, Equatable {
        let rawValue: String
    }

    @Test("Optional RawRepresentable value returns default value when not set")
    func testOptionalRawRepresentableValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
    }

    @Test("Optional RawRepresentable value returns nil when no default is set")
    func testOptionalRawRepresentableValueNilValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .test, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional RawRepresentable value is updated correctly")
    func testOptionalRawRepresentableValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "new"))
        #expect((defaults.dictionary as! [String: String]) == ["test": "new"])
    }

    @Test("Optional RawRepresentable value is removed correctly")
    func testOptionalRawRepresentableValueRemoval() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional RawRepresentable value is cleared correctly")
    func testOptionalRawRepresentableValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional RawRepresentable value works with shared defaults")
    func testOptionalRawRepresentableValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .test, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "new"))

        UserDefaultsWrapper<MyRawRepresentable?>(key: .test, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: RawRepresentable with enum Key

    @Test("RawRepresentable value returns default value when not set with enum key")
    func testRawRepresentableValueDefaultValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
    }

    @Test("RawRepresentable value is updated correctly with enum key")
    func testRawRepresentableValueUpdatingWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "new"))
        #expect((defaults.dictionary as! [String: String]) == ["test": "new"])
    }

    @Test("RawRepresentable value is cleared correctly with enum key")
    func testRawRepresentableValueClearWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        wrapper.clear()
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("RawRepresentable value works with shared defaults with enum key")
    func testRawRepresentableValueSharedDefaultsWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "new"))

        UserDefaultsWrapper<MyRawRepresentable>(key: .test, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults).clear()
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: Optional<RawRepresentable> with enum Key

    @Test("Optional RawRepresentable value returns default value when not set with enum key")
    func testOptionalRawRepresentableValueDefaultValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .lastCrashReportCheckDate, defaultValue: MyRawRepresentable(rawValue: "value"), defaults: defaults)
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "value"))
    }

    @Test("Optional RawRepresentable value returns nil when no default is set with enum key")
    func testOptionalRawRepresentableValueNilValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional RawRepresentable value is updated correctly with enum key")
    func testOptionalRawRepresentableValueUpdatingWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "new"))
        #expect((defaults.dictionary as! [String: String]) == [UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue: "new"])
    }

    @Test("Optional RawRepresentable value is removed correctly with enum key")
    func testOptionalRawRepresentableValueRemovalWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional RawRepresentable value is cleared correctly with enum key")
    func testOptionalRawRepresentableValueClearWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional RawRepresentable value works with shared defaults with enum key")
    func testOptionalRawRepresentableValueSharedDefaultsWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<MyRawRepresentable?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = MyRawRepresentable(rawValue: "new")
        #expect(wrapper.wrappedValue == MyRawRepresentable(rawValue: "new"))

        UserDefaultsWrapper<MyRawRepresentable?>(key: .lastCrashReportCheckDate, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue) == nil)
    }

    // MARK: Date

    let date1 = Date()
    let date2 = Date().addingTimeInterval(1)

    @Test("Date value returns default value when not set")
    func testDateValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .lastCrashReportCheckDate, defaultValue: date1, defaults: defaults)
        #expect(wrapper.wrappedValue == date1)
    }

    @Test("Date value is updated correctly")
    func testDateValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .lastCrashReportCheckDate, defaultValue: date1, defaults: defaults)
        wrapper.wrappedValue = date2
        #expect(wrapper.wrappedValue == date2)
        #expect((defaults.dictionary as! [String: Date]) == [UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue: date2])
    }

    @Test("Date value is cleared correctly")
    func testDateValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .lastCrashReportCheckDate, defaultValue: date1, defaults: defaults)
        wrapper.wrappedValue = date2
        wrapper.clear()
        #expect(wrapper.wrappedValue == date1)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Date value works with shared defaults")
    func testDateValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .lastCrashReportCheckDate, defaultValue: date1, defaults: defaults)
        #expect(wrapper.wrappedValue == date1)
        wrapper.wrappedValue = date2
        #expect(wrapper.wrappedValue == date2)

        UserDefaultsWrapper<Date>(key: .lastCrashReportCheckDate, defaultValue: date1, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == date1)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue) == nil)
    }

    // MARK: Optional<Date>

    @Test("Optional Date value returns default value when not set")
    func testOptionalDateValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaultValue: date1, defaults: defaults)
        #expect(wrapper.wrappedValue == date1)
    }

    @Test("Optional Date value returns nil when no default is set")
    func testOptionalDateValueNilValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional Date value is updated correctly")
    func testOptionalDateValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = date2
        #expect(wrapper.wrappedValue == date2)
        #expect((defaults.dictionary as! [String: Date]) == [UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue: date2])
    }

    @Test("Optional Date value is removed correctly")
    func testOptionalDateValueRemoval() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = date2
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Date value is cleared correctly")
    func testOptionalDateValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = date2
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Date value works with shared defaults")
    func testOptionalDateValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = date2
        #expect(wrapper.wrappedValue == date2)

        UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue) == nil)
    }

    // MARK: Optional<Date> with enum Key

    @Test("Optional Date value returns default value when not set with enum key")
    func testOptionalDateValueDefaultValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaultValue: date1, defaults: defaults)
        #expect(wrapper.wrappedValue == date1)
    }

    @Test("Optional Date value returns nil when no default is set with enum key")
    func testOptionalDateValueNilValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional Date value is updated correctly with enum key")
    func testOptionalDateValueUpdatingWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = date2
        #expect(wrapper.wrappedValue == date2)
        #expect((defaults.dictionary as! [String: Date]) == [UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue: date2])
    }

    @Test("Optional Date value is removed correctly with enum key")
    func testOptionalDateValueRemovalWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = date2
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Date value is cleared correctly with enum key")
    func testOptionalDateValueClearWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = date2
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Date value works with shared defaults with enum key")
    func testOptionalDateValueSharedDefaultsWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = date2
        #expect(wrapper.wrappedValue == date2)

        UserDefaultsWrapper<Date?>(key: .lastCrashReportCheckDate, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue) == nil)
    }

    // MARK: Bool

    @Test("Bool value returns default value when not set")
    func testBoolValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: true, defaults: defaults)
        #expect(wrapper.wrappedValue == true)
    }

    @Test("Bool value is updated correctly")
    func testBoolValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: true, defaults: defaults)
        wrapper.wrappedValue = false
        #expect(wrapper.wrappedValue == false)
        #expect((defaults.dictionary as! [String: Bool]) == ["test": false])
    }

    @Test("Bool value is cleared correctly")
    func testBoolValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: true, defaults: defaults)
        wrapper.wrappedValue = false
        wrapper.clear()
        #expect(wrapper.wrappedValue == true)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Bool value works with shared defaults")
    func testBoolValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper(key: .test, defaultValue: true, defaults: defaults)
        #expect(wrapper.wrappedValue == true)
        wrapper.wrappedValue = false
        #expect(wrapper.wrappedValue == false)

        UserDefaultsWrapper<Bool>(key: .test, defaultValue: true, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == true)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: Optional<Bool>

    @Test("Optional Bool value returns default value when not set")
    func testOptionalBoolValueDefaultValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .test, defaultValue: true, defaults: defaults)
        #expect(wrapper.wrappedValue == true)
    }

    @Test("Optional Bool value returns nil when no default is set")
    func testOptionalBoolValueNilValue() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .test, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional Bool value is updated correctly")
    func testOptionalBoolValueUpdating() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = false
        #expect(wrapper.wrappedValue == false)
        #expect((defaults.dictionary as! [String: Bool]) == ["test": false])
    }

    @Test("Optional Bool value is removed correctly")
    func testOptionalBoolValueRemoval() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = false
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Bool value is cleared correctly")
    func testOptionalBoolValueClear() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .test, defaults: defaults)
        wrapper.wrappedValue = false
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Bool value works with shared defaults")
    func testOptionalBoolValueSharedDefaults() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .test, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = false
        #expect(wrapper.wrappedValue == false)

        UserDefaultsWrapper<Bool?>(key: .test, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapperKey.test.rawValue) == nil)
    }

    // MARK: Optional<Bool> with enum Key

    @Test("Optional Bool value returns default value when not set with enum key")
    func testOptionalBoolValueDefaultValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .lastCrashReportCheckDate, defaultValue: true, defaults: defaults)
        #expect(wrapper.wrappedValue == true)
    }

    @Test("Optional Bool value returns nil when no default is set with enum key")
    func testOptionalBoolValueNilValueWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("Optional Bool value is updated correctly with enum key")
    func testOptionalBoolValueUpdatingWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = false
        #expect(wrapper.wrappedValue == false)
        #expect((defaults.dictionary as! [String: Bool]) == [UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue: false])
    }

    @Test("Optional Bool value is removed correctly with enum key")
    func testOptionalBoolValueRemovalWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = false
        wrapper.wrappedValue = nil
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Bool value is cleared correctly with enum key")
    func testOptionalBoolValueClearWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .lastCrashReportCheckDate, defaults: defaults)
        wrapper.wrappedValue = false
        wrapper.clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(defaults.dictionary.isEmpty)
    }

    @Test("Optional Bool value works with shared defaults with enum key")
    func testOptionalBoolValueSharedDefaultsWithEnumKey() {
        let defaults = UserDefaultsMock()
        let wrapper = UserDefaultsWrapper<Bool?>(key: .lastCrashReportCheckDate, defaults: defaults)
        #expect(wrapper.wrappedValue == nil)
        wrapper.wrappedValue = false
        #expect(wrapper.wrappedValue == false)

        UserDefaultsWrapper<Bool?>(key: .lastCrashReportCheckDate, defaults: defaults).clear()
        #expect(wrapper.wrappedValue == nil)
        #expect(UserDefaultsWrapper<Any>.sharedDefaults.object(forKey: UserDefaultsWrapper<Any>.Key.lastCrashReportCheckDate.rawValue) == nil)
    }
}

private final class UserDefaultsMock: UserDefaults {
    var dictionary: [String: Any] = [:]

    init(_ dictionary: [String: Any] = [:]) {
        self.dictionary = dictionary
        super.init(suiteName: nil)!
    }

    override func dictionaryRepresentation() -> [String: Any] {
        dictionary
    }

    override func object(forKey key: String) -> Any? {
        dictionary[key]
    }

    override func set(_ value: Any?, forKey key: String) {
        dictionary[key] = value
    }

    override func removeObject(forKey key: String) {
        dictionary[key] = nil
    }

}
