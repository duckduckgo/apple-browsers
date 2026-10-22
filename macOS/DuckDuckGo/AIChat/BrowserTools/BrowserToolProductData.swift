//
//  BrowserToolProductData.swift
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

import AIChat
import Foundation
import WebKit

/// One product a page declares about itself. Prices stay strings: retailers format them too
/// inconsistently to parse, and the model reads them fine as they are.
struct BrowserToolProduct: Equatable {
    var name: String?
    var price: String?
    var currency: String?
    var availability: String?
    var url: String?
    var brand: String?
    var sku: String?

    /// Absent fields are left out, never sent as null.
    var jsonValue: JSONValue {
        let fields: [String: String?] = [
            "name": name,
            "price": price,
            "currency": currency,
            "availability": availability,
            "url": url,
            "brand": brand,
            "sku": sku
        ]
        return .object(fields.compactMapValues { $0 }.mapValues(JSONValue.string))
    }
}

/// Product data for `readTabContent`, behind a seam so the tool is testable without a web view.
@MainActor
protocol BrowserToolProductDataReading: AnyObject {
    func products(forTabID tabID: TabIdentifier, in collection: TabCollectionViewModel) async -> [BrowserToolProduct]
}

/// Collects the raw material in the page and parses it here, so the page script stays small and
/// the parsing is unit-testable. Runs in the page world, the same one the page-content reader uses.
@MainActor
final class WebViewProductDataReader: BrowserToolProductDataReading {

    func products(forTabID tabID: TabIdentifier, in collection: TabCollectionViewModel) async -> [BrowserToolProduct] {
        guard let tab = BrowserToolTargetTab.attachableTab(withID: tabID, in: collection),
              let raw = try? await tab.webView.callAsyncJavaScript(Self.script, arguments: [:], in: nil, contentWorld: .page),
              let pageData = JSONValue(bridgeValue: raw) else {
            return []
        }
        return BrowserToolProductParser.products(fromPageData: pageData)
    }

    /// Returns `{ld: [String], meta: {String: String}, microdata: [{String: String}]}`.
    static let script = """
    const maxBlocks = \(BrowserToolProductParser.maxProducts);
    const maxBlockLength = 100000;
    const text = (value) => (value || '').trim().slice(0, 500);

    const ld = [];
    for (const script of document.querySelectorAll('script[type="application/ld+json" i]')) {
        if (ld.length >= maxBlocks) break;
        const content = script.textContent || '';
        if (content.length <= maxBlockLength) ld.push(content);
    }

    const meta = {};
    const metaKey = /^(og:(price:amount|price:currency|title|url|availability|brand)|product:(price:amount|price:currency|availability|brand|retailer_item_id))$/;
    for (const element of document.querySelectorAll('meta[property], meta[name]')) {
        const key = (element.getAttribute('property') || element.getAttribute('name') || '').toLowerCase();
        if (metaKey.test(key) && !(key in meta)) meta[key] = text(element.getAttribute('content'));
    }

    const read = (scope, property) => {
        const element = scope.querySelector('[itemprop="' + property + '"]');
        if (!element) return '';
        return text(element.getAttribute('content') || element.getAttribute('href') || element.textContent);
    };
    const microdataEntry = (scope) => ({
        name: read(scope, 'name'),
        price: read(scope, 'price'),
        currency: read(scope, 'priceCurrency'),
        availability: read(scope, 'availability'),
        url: read(scope, 'url'),
        brand: read(scope, 'brand'),
        sku: read(scope, 'sku')
    });
    const scopes = Array.from(document.querySelectorAll('[itemscope][itemtype*="schema.org/Product" i]')).slice(0, maxBlocks);
    const hasPagePrice = document.querySelector('[itemprop="price"]') !== null;
    const microdata = scopes.length > 0 ? scopes.map(microdataEntry) : (hasPagePrice ? [microdataEntry(document)] : []);

    return { ld, meta, microdata };
    """
}

/// Finds products in what the page script collected. JSON-LD comes first; `og:`/`product:` meta
/// tags, then microdata, are fallbacks for pages without it.
enum BrowserToolProductParser {

    static let maxProducts = 20

    private static let maxDepth = 8

    static func products(fromPageData pageData: JSONValue) -> [BrowserToolProduct] {
        products(jsonLD: pageData["ld"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                 meta: pageData["meta"]?.objectValue?.compactMapValues(\.stringValue) ?? [:],
                 microdata: pageData["microdata"]?.arrayValue?.compactMap { $0.objectValue?.compactMapValues(\.stringValue) } ?? [])
    }

    static func products(jsonLD: [String], meta: [String: String], microdata: [[String: String]]) -> [BrowserToolProduct] {
        var products: [BrowserToolProduct] = []
        for block in jsonLD {
            // One broken block must not hide the products in the others.
            guard let document = try? JSONValue(jsonString: block) else { continue }
            collectProducts(in: document, depth: 0, into: &products)
        }
        if products.isEmpty, let product = product(fromMeta: meta) {
            products = [product]
        }
        if products.isEmpty {
            products = microdata.compactMap(product(fromMicrodata:))
        }
        return Array(products.prefix(maxProducts))
    }

    // MARK: - JSON-LD

    /// Walks `@graph`, arrays and nested entities such as `mainEntity`. A product's own children are
    /// not searched, so its variants and offers are not reported as separate products.
    private static func collectProducts(in node: JSONValue, depth: Int, into products: inout [BrowserToolProduct]) {
        guard depth <= maxDepth, products.count < maxProducts else { return }
        switch node {
        case .array(let items):
            for item in items {
                collectProducts(in: item, depth: depth + 1, into: &products)
            }
        case .object(let object):
            if isProduct(object) {
                if let product = product(fromJSONLD: object) {
                    products.append(product)
                }
                return
            }
            // Sorted so the order does not depend on dictionary ordering.
            for key in object.keys.sorted() {
                if let value = object[key] {
                    collectProducts(in: value, depth: depth + 1, into: &products)
                }
            }
        default:
            break
        }
    }

    /// `@type` may be a string or an array, and may be a full IRI such as `https://schema.org/Product`.
    private static func isProduct(_ object: [String: JSONValue]) -> Bool {
        let types: [String]
        switch object["@type"] {
        case .string(let type): types = [type]
        case .array(let items): types = items.compactMap(\.stringValue)
        default: types = []
        }
        return types.contains { schemaName($0) == "Product" }
    }

    private static func product(fromJSONLD object: [String: JSONValue]) -> BrowserToolProduct? {
        let offer = pricedOffer(in: object["offers"])
        let specification = offer.flatMap { priceSpecification(in: $0["priceSpecification"]) }
        let product = BrowserToolProduct(
            name: text(object["name"]),
            price: offer.flatMap { text($0["price"]) ?? text($0["lowPrice"]) } ?? specification.flatMap { text($0["price"]) },
            currency: offer.flatMap { text($0["priceCurrency"]) } ?? specification.flatMap { text($0["priceCurrency"]) },
            availability: offer.flatMap { text($0["availability"]) }.map(availabilityName),
            url: text(object["url"]) ?? offer.flatMap { text($0["url"]) },
            brand: text(object["brand"]) ?? text(object["brand"]?["name"]) ?? text(object["brand"]?.arrayValue?.first?["name"]),
            sku: text(object["sku"])
        )
        return product.name == nil && product.price == nil ? nil : product
    }

    /// An `Offer`, an `AggregateOffer`, or an array of either; from an array, the first with a price.
    private static func pricedOffer(in offers: JSONValue?) -> [String: JSONValue]? {
        switch offers {
        case .object(let offer):
            return offer
        case .array(let items):
            let offers = items.compactMap(\.objectValue)
            return offers.first { (text($0["price"]) ?? text($0["lowPrice"])) != nil } ?? offers.first
        default:
            return nil
        }
    }

    private static func priceSpecification(in value: JSONValue?) -> [String: JSONValue]? {
        switch value {
        case .object(let specification): specification
        case .array(let items): items.compactMap(\.objectValue).first { text($0["price"]) != nil }
        default: nil
        }
    }

    // MARK: - Fallbacks

    /// Needs a price: every page has an `og:title`, so a title alone says nothing about a product.
    private static func product(fromMeta meta: [String: String]) -> BrowserToolProduct? {
        guard let price = nonEmpty(meta["og:price:amount"]) ?? nonEmpty(meta["product:price:amount"]) else { return nil }
        return BrowserToolProduct(name: nonEmpty(meta["og:title"]),
                                  price: price,
                                  currency: nonEmpty(meta["og:price:currency"]) ?? nonEmpty(meta["product:price:currency"]),
                                  availability: (nonEmpty(meta["product:availability"]) ?? nonEmpty(meta["og:availability"])).map(availabilityName),
                                  url: nonEmpty(meta["og:url"]),
                                  brand: nonEmpty(meta["product:brand"]) ?? nonEmpty(meta["og:brand"]),
                                  sku: nonEmpty(meta["product:retailer_item_id"]))
    }

    private static func product(fromMicrodata fields: [String: String]) -> BrowserToolProduct? {
        let product = BrowserToolProduct(name: nonEmpty(fields["name"]),
                                         price: nonEmpty(fields["price"]),
                                         currency: nonEmpty(fields["currency"]),
                                         availability: nonEmpty(fields["availability"]).map(availabilityName),
                                         url: nonEmpty(fields["url"]),
                                         brand: nonEmpty(fields["brand"]),
                                         sku: nonEmpty(fields["sku"]))
        return product.name == nil && product.price == nil ? nil : product
    }

    // MARK: - Values

    /// Numbers are allowed because many sites write `"price": 19.99` or a numeric sku.
    private static func text(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let string):
            return nonEmpty(string)
        case .int(let int):
            return String(int)
        case .double(let double):
            if double == double.rounded(), let int = Int(exactly: double) {
                return String(int)
            }
            return String(double)
        default:
            return nil
        }
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// `https://schema.org/Product` and `schema:Product` → `Product`.
    private static func schemaName(_ type: String) -> String {
        type.components(separatedBy: CharacterSet(charactersIn: "/:#")).last(where: { !$0.isEmpty }) ?? type
    }

    /// `https://schema.org/InStock` → `InStock`. Free text such as "Ships in: 2 days" is kept whole.
    private static func availabilityName(_ value: String) -> String {
        guard value.lowercased().contains("schema.org") else { return value }
        return schemaName(value)
    }
}
