//
//  PixelKitFiring.swift
//  DuckDuckGo
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

import PixelKit

/// PixelKit's `PixelFiring`, under a name that does not collide with `Core.PixelFiring`.
///
/// Any file importing both modules sees an ambiguous `PixelFiring`. Once `Core.PixelFiring` is
/// deleted the ambiguity goes with it and this typealias can be renamed away.
typealias PixelKitFiring = PixelFiring
