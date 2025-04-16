//
//  FrameHandle.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import WebKit

#if _FRAME_HANDLE_ENABLED
public struct FrameHandle: Hashable, _ObjectiveCBridgeable {
    private let rawValue: Any

    private static let frameIDKey = "frameID"

    public var frameID: UInt64 {
        guard let object = rawValue as? NSObject,
              object.responds(to: NSSelectorFromString("_" + Self.frameIDKey)) || object.responds(to: NSSelectorFromString(Self.frameIDKey)) else {
            return rawValue as? UInt64 ?? 0
        }
        return object.value(forKey: Self.frameIDKey) as? UInt64 ?? 0
    }

    public init?(rawValue: Any) {
        guard rawValue is UInt64
                || (rawValue as? NSObject)?.responds(to: NSSelectorFromString("_" + Self.frameIDKey)) == true
                || (rawValue as? NSObject)?.responds(to: NSSelectorFromString(Self.frameIDKey)) == true
        else {
            assertionFailure("Could not convert \(rawValue) to FrameHandle")
            return nil
        }
        self.rawValue = rawValue
    }

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func == (lhs: FrameHandle, rhs: FrameHandle) -> Bool {
        assert(lhs.frameID != 0)
        assert(rhs.frameID != 0)
        return lhs.frameID == rhs.frameID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(frameID)
    }

    // swiftlint:disable identifier_name

    public func _bridgeToObjectiveC() -> NSObject {
        return rawValue as? NSObject ?? NSObject()
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSObject, result: inout FrameHandle?) -> Bool {
        result = FrameHandle(rawValue: source)
        return result != nil
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSObject, result: inout FrameHandle?) {
        _=_conditionallyBridgeFromObjectiveC(source, result: &result)
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSObject?) -> FrameHandle {
        var result: FrameHandle!
        _=_conditionallyBridgeFromObjectiveC(source!, result: &result)
        return result
    }

    // swiftlint:enable identifier_name

    // fallback values
    public static var fallbackMainFrameHandle: FrameHandle {
        FrameHandle(rawValue: WKFrameInfo.defaultMainFrameHandle)
    }

    public static var fallbackNonMainFrameHandle: FrameHandle {
        FrameHandle(rawValue: WKFrameInfo.defaultNonMainFrameHandle)
    }

}

extension FrameHandle: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(frameID)"
    }
}
#endif
