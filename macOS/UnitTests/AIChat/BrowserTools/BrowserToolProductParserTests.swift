//
//  BrowserToolProductParserTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class BrowserToolProductParserTests: XCTestCase {

    // MARK: - JSON-LD

    func testWhenABlockIsAProductWithAnOfferThenAllItsFieldsAreRead() {
        let products = parse(jsonLD: ["""
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "Kettle",
          "sku": "K-1",
          "brand": {"@type": "Brand", "name": "Acme"},
          "url": "https://shop.example/kettle",
          "offers": {
            "@type": "Offer",
            "price": "39.99",
            "priceCurrency": "USD",
            "availability": "https://schema.org/InStock"
          }
        }
        """])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "39.99", currency: "USD", availability: "InStock",
                                                     url: "https://shop.example/kettle", brand: "Acme", sku: "K-1")])
    }

    func testWhenProductsSitInAGraphThenEachIsFoundInOrder() {
        let products = parse(jsonLD: ["""
        {
          "@context": "https://schema.org",
          "@graph": [
            {"@type": "WebPage", "name": "Kettles"},
            {"@type": "Product", "name": "Kettle", "offers": {"@type": "Offer", "price": 39.99, "priceCurrency": "USD"}},
            {"@type": "Product", "name": "Toaster", "offers": {"@type": "Offer", "price": 25, "priceCurrency": "USD"}}
          ]
        }
        """])

        XCTAssertEqual(products.map(\.name), ["Kettle", "Toaster"])
        XCTAssertEqual(products.map(\.price), ["39.99", "25"])
    }

    func testWhenTheBlockIsATopLevelArrayThenProductsInsideAreFound() {
        let products = parse(jsonLD: ["""
        [{"@type": "BreadcrumbList"}, {"@type": "Product", "name": "Kettle", "offers": {"price": "39.99"}}]
        """])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "39.99")])
    }

    func testWhenTypeIsAnArrayOrAFullIRIThenItIsStillAProduct() {
        let products = parse(jsonLD: [
            #"{"@type": ["Product", "Thing"], "name": "Kettle"}"#,
            #"{"@type": "http://schema.org/Product", "name": "Toaster"}"#
        ])

        XCTAssertEqual(products.map(\.name), ["Kettle", "Toaster"])
    }

    func testWhenTheProductIsNestedAsMainEntityThenItIsFound() {
        let products = parse(jsonLD: [#"{"@type": "ItemPage", "mainEntity": {"@type": "Product", "name": "Kettle"}}"#])

        XCTAssertEqual(products.map(\.name), ["Kettle"])
    }

    func testWhenTheOfferIsAnAggregateOfferWithoutAPriceThenTheLowPriceIsUsed() {
        let products = parse(jsonLD: ["""
        {"@type": "Product", "name": "Kettle",
         "offers": {"@type": "AggregateOffer", "lowPrice": "29.00", "highPrice": "49.00", "priceCurrency": "EUR", "offerCount": 4}}
        """])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "29.00", currency: "EUR")])
    }

    func testWhenOffersAreAnArrayThenTheFirstOfferWithAPriceIsUsed() {
        let products = parse(jsonLD: ["""
        {"@type": "Product", "name": "Kettle",
         "offers": [
           {"@type": "Offer", "availability": "https://schema.org/OutOfStock"},
           {"@type": "Offer", "price": "41.50", "priceCurrency": "GBP", "availability": "https://schema.org/InStock"},
           {"@type": "Offer", "price": "39.00", "priceCurrency": "GBP"}
         ]}
        """])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "41.50", currency: "GBP", availability: "InStock")])
    }

    func testWhenTheOfferOnlyHasAPriceSpecificationThenItsPriceIsUsed() {
        let products = parse(jsonLD: ["""
        {"@type": "Product", "name": "Kettle",
         "offers": {"@type": "Offer", "priceSpecification": [{"@type": "UnitPriceSpecification", "price": 19.5, "priceCurrency": "USD"}]}}
        """])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "19.5", currency: "USD")])
    }

    func testWhenNumbersAreUsedForPriceAndSkuThenTheyBecomeStrings() {
        let products = parse(jsonLD: [#"{"@type": "Product", "name": "Kettle", "sku": 12345, "offers": {"price": 1299.0}}"#])

        XCTAssertEqual(products.first?.price, "1299")
        XCTAssertEqual(products.first?.sku, "12345")
    }

    func testWhenBrandIsAPlainStringThenItIsUsed() {
        let products = parse(jsonLD: [#"{"@type": "Product", "name": "Kettle", "brand": "Acme"}"#])

        XCTAssertEqual(products.first?.brand, "Acme")
    }

    /// One malformed block must not hide the products in the others.
    func testWhenABlockIsBrokenJSONThenItIsSkippedAndTheOthersStillParse() {
        let products = parse(jsonLD: [
            #"{"@type": "Product", "name": "Broken", "offers": {"price": "1.00",}"#,
            "not json at all",
            "",
            #"{"@type": "Product", "name": "Kettle", "offers": {"price": "39.99"}}"#
        ])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "39.99")])
    }

    func testWhenFieldsAreMissingOrBlankThenTheyAreLeftOut() throws {
        let products = parse(jsonLD: [#"{"@type": "Product", "name": "Kettle", "sku": "  ", "offers": {"price": "39.99", "priceCurrency": ""}}"#])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "39.99")])
        XCTAssertEqual(try XCTUnwrap(products.first).jsonValue, ["name": "Kettle", "price": "39.99"])
    }

    func testWhenAProductHasNeitherNameNorPriceThenItIsDropped() {
        let products = parse(jsonLD: [#"{"@type": "Product", "sku": "K-1"}"#])

        XCTAssertTrue(products.isEmpty)
    }

    /// Variants and offers inside a product are part of it, not products of their own.
    func testWhenAProductContainsNestedProductsThenOnlyTheOuterOneIsReported() {
        let products = parse(jsonLD: [#"{"@type": "Product", "name": "Kettle", "isSimilarTo": {"@type": "Product", "name": "Toaster"}}"#])

        XCTAssertEqual(products.map(\.name), ["Kettle"])
    }

    func testWhenThereAreMoreThanTwentyProductsThenOnlyTwentyAreReturned() {
        let items = (0..<30).map { #"{"@type": "Product", "name": "Item \#($0)"}"# }.joined(separator: ",")

        let products = parse(jsonLD: ["[\(items)]"])

        XCTAssertEqual(products.count, BrowserToolProductParser.maxProducts)
        XCTAssertEqual(products.first?.name, "Item 0")
    }

    // MARK: - Fallbacks

    func testWhenThereIsNoJSONLDThenPriceMetaTagsAreUsed() {
        let products = parse(meta: [
            "og:title": "Kettle",
            "og:price:amount": "39.99",
            "og:price:currency": "USD",
            "og:url": "https://shop.example/kettle",
            "product:availability": "in stock"
        ])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "39.99", currency: "USD", availability: "in stock",
                                                     url: "https://shop.example/kettle")])
    }

    func testWhenOnlyProductPriceMetaTagsExistThenTheyAreUsed() {
        let products = parse(meta: ["product:price:amount": "12.00", "product:price:currency": "EUR"])

        XCTAssertEqual(products, [BrowserToolProduct(price: "12.00", currency: "EUR")])
    }

    /// Every page has an `og:title`; without a price it says nothing about a product.
    func testWhenMetaTagsHaveNoPriceThenNoProductIsReported() {
        let products = parse(meta: ["og:title": "About us"])

        XCTAssertTrue(products.isEmpty)
    }

    func testWhenThereIsNoJSONLDOrPriceMetaThenMicrodataIsUsed() {
        let products = parse(microdata: [
            ["name": "Kettle", "price": "39.99", "currency": "USD", "availability": "https://schema.org/InStock", "sku": "", "url": ""],
            ["name": "", "price": ""]
        ])

        XCTAssertEqual(products, [BrowserToolProduct(name: "Kettle", price: "39.99", currency: "USD", availability: "InStock")])
    }

    func testWhenJSONLDHasProductsThenTheFallbacksAreIgnored() {
        let products = parse(jsonLD: [#"{"@type": "Product", "name": "Kettle"}"#],
                             meta: ["og:price:amount": "1.00"],
                             microdata: [["name": "Other", "price": "2.00"]])

        XCTAssertEqual(products.map(\.name), ["Kettle"])
    }

    // MARK: - Page data

    /// The shape the in-page script returns.
    func testWhenPageDataIsReadThenEachPartIsPassedOn() throws {
        let pageData = try JSONValue(jsonString: """
        {"ld": ["{\\"@type\\": \\"Product\\", \\"name\\": \\"Kettle\\"}"], "meta": {}, "microdata": []}
        """)

        XCTAssertEqual(BrowserToolProductParser.products(fromPageData: pageData).map(\.name), ["Kettle"])
    }

    func testWhenPageDataIsMalformedThenThereAreNoProducts() {
        XCTAssertTrue(BrowserToolProductParser.products(fromPageData: "nope").isEmpty)
        XCTAssertTrue(BrowserToolProductParser.products(fromPageData: ["ld": 3, "meta": [], "microdata": "x"]).isEmpty)
    }

    // MARK: -

    private func parse(jsonLD: [String] = [], meta: [String: String] = [:], microdata: [[String: String]] = []) -> [BrowserToolProduct] {
        BrowserToolProductParser.products(jsonLD: jsonLD, meta: meta, microdata: microdata)
    }
}
