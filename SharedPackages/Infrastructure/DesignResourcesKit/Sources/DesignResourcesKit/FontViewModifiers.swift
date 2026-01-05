//
//  FontViewModifiers.swift
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

import Foundation
import SwiftUI

#if canImport(UIKit)

public struct DaxTitle1: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxTitle1()))
    }
}

public struct DaxTitle2: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxTitle2()))
    }
}

public struct DaxTitle3: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxTitle3()))
    }
}

public struct DaxHeadline: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxHeadline()))
    }
}

public struct DaxBodyRegular: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxBodyRegular()))
    }
}

public struct DaxBodyBold: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxBodyBold()))
    }
}

public struct DaxSubheadRegular: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxSubheadRegular()))
    }
}

public struct DaxSubheadSemibold: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxSubheadSemibold()))
    }
}

public struct DaxButton: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxButton()))
    }
}

public struct DaxFootnoteRegular: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxFootnoteRegular()))
    }
}

public struct DaxFootnoteSemibold: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxFootnoteSemibold()))
    }
}

public struct DaxCaption: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Font(UIFont.daxCaption()))
    }
}

public extension View {
    func daxTitle1() -> some View {
        modifier(DaxTitle1())
    }

    func daxTitle2() -> some View {
        modifier(DaxTitle2())
    }

    func daxTitle3() -> some View {
        modifier(DaxTitle3())
    }

    func daxHeadline() -> some View {
        modifier(DaxHeadline())
    }

    func daxBodyRegular() -> some View {
        modifier(DaxBodyRegular())
    }

    func daxBodyBold() -> some View {
        modifier(DaxBodyBold())
    }

    func daxSubheadRegular() -> some View {
        modifier(DaxSubheadRegular())
    }

    func daxSubheadSemibold() -> some View {
        modifier(DaxSubheadSemibold())
    }

    func daxButton() -> some View {
        modifier(DaxButton())
    }

    func daxFootnoteRegular() -> some View {
        modifier(DaxFootnoteRegular())
    }

    func daxFootnoteSemibold() -> some View {
        modifier(DaxFootnoteSemibold())
    }

    func daxCaption() -> some View {
        modifier(DaxCaption())
    }
}

#endif
