//
//  NewTabPageBlock.swift
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

import UIKit

/// One unit of New Tab Page content. Blocks are stacked vertically in the order given.
///
/// `id` is a stable string key for the block's persisted order and visibility.
protocol NewTabPageBlock: AnyObject, Identifiable where ID == String {

    /// The block's content, installed as a child view controller of the page.
    var viewController: UIViewController { get }
}
