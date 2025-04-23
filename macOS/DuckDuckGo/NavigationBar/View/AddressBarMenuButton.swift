//
//  AddressBarMenuButton.swift
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

import Cocoa

/// A specialized button class for forwarding mouse events in `AddressBarViewController`.
///
/// `AddressBarMenuButton` extends `AddressBarButton` to handle forwarding mouse events, especially the right mouse button down event which are used to trigger the NSMenu.
/// This makes sure `AddressBarViewController` processes these events correctly in `func rightMouseDown(with event: NSEvent) -> NSEvent?`.
///
/// For more details, see the [Asana Task](https://app.asana.com/1/137249556945/project/1177771139624306/task/1203899219213416?focus=true).
///
internal class AddressBarMenuButton: AddressBarButton { }
