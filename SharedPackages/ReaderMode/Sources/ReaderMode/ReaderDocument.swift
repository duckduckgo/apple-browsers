//
//  ReaderDocument.swift
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

import DesignResourcesKit
import Foundation
import SwiftSoup
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum ReaderDocument {

    /// Extracted content comes from an arbitrary page, so the policy keeps any script that slips through from running.
    static let contentSecurityPolicy = "default-src 'none'; img-src https: http:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-src 'none'; upgrade-insecure-requests"

    public static func html(for article: ReaderArticle, theme: ReaderTheme) -> String {
        let siteLine = article.siteName.map { "<p class=\"site\">\(escape($0))</p>\n" } ?? ""
        let byline = article.author.map { "<p class=\"byline\">\(escape($0))</p>\n" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="referrer" content="no-referrer">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(article.title))</title>
        <style>
        \(colors(theme))
        \(style)
        </style>
        </head>
        <body>
        <article>
        \(siteLine)<h1>\(escape(article.title))</h1>
        \(byline)\(article.contentHTML)
        </article>
        </body>
        </html>
        """
    }

    /// Keeps a semantic subset of the extracted HTML with absolute http and https links and images only.
    static func sanitize(_ content: String, title: String, author: String?, baseURL: URL) throws -> String {
        let document = try SwiftSoup.parseBodyFragment(content)
        try document.select("script, style, iframe, frame, frameset, form, input, button, textarea, select, object, embed, svg, math, template").remove()
        for element in try document.select("a[href], img[src]") {
            let attribute = element.tagName() == "a" ? "href" : "src"
            let value = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
               ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                try element.attr(attribute, url.absoluteString)
            } else {
                try element.removeAttr(attribute)
            }
        }
        if let heading = document.body()?.children().first(), heading.tagName() == "h1", try heading.text() == title {
            try heading.remove()
        }
        if let author, let byline = document.body()?.children().first(), byline.tagName() == "p", try byline.text() == author {
            try byline.remove()
        }
        let allowlist = try Whitelist.none()
            .addTags("article", "section", "div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "a", "img",
                     "figure", "figcaption", "blockquote", "pre", "code", "ul", "ol", "li", "dl", "dt", "dd",
                     "strong", "em", "b", "i", "u", "s", "sup", "sub", "br", "hr", "table", "thead", "tbody", "tfoot", "tr", "th", "td", "caption")
            .addAttributes(":all", "id")
            .addAttributes("a", "href")
            .addAttributes("img", "src", "alt")
            .addProtocols("a", "href", "http", "https")
            .addProtocols("img", "src", "http", "https")
        let settings = OutputSettings().prettyPrint(pretty: false)
        return try SwiftSoup.clean(document.body()?.html() ?? "", baseURL.absoluteString, allowlist, settings) ?? ""
    }

    static func escape(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
    }

    private static func colors(_ theme: ReaderTheme) -> String {
        func variables(_ appearance: KeyPath<ReaderTheme.ColorPair, ReaderTheme.Color>) -> String {
            """
            --text: \(theme.text[keyPath: appearance].css);
            --secondary: \(theme.secondaryText[keyPath: appearance].css);
            --background: \(theme.background[keyPath: appearance].css);
            --link: \(theme.link[keyPath: appearance].css);
            --code-background: \(theme.codeBackground[keyPath: appearance].css);
            --rule: \(theme.border[keyPath: appearance].css);
            """
        }
        return """
        :root { color-scheme: light dark; \(variables(\ReaderTheme.ColorPair.light)) }
        @media (prefers-color-scheme: dark) { :root { \(variables(\ReaderTheme.ColorPair.dark)) } }
        """
    }

    private static let style = """
    html { background: var(--background); }
    body {
        margin: 0;
        padding: 48px 24px 96px;
        color: var(--text);
        background: var(--background);
        font: 19px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        -webkit-font-smoothing: antialiased;
    }
    article { max-width: 680px; margin: 0 auto; overflow-wrap: break-word; }
    .site { margin: 0 0 8px; color: var(--secondary); font-size: 15px; text-transform: uppercase; letter-spacing: 0.04em; }
    h1 { margin: 0 0 32px; font-size: 34px; line-height: 1.2; }
    .byline { margin: -24px 0 32px; color: var(--secondary); font-size: 15px; }
    h2, h3, h4 { line-height: 1.3; margin: 1.6em 0 0.6em; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    img, video, figure { max-width: 100%; height: auto; }
    figure { margin: 1.5em 0; }
    figcaption { color: var(--secondary); font-size: 15px; }
    blockquote { margin: 1.5em 0; padding-left: 1em; border-left: 3px solid var(--rule); color: var(--secondary); }
    pre, code { font: 15px/1.5 ui-monospace, Menlo, monospace; }
    pre { overflow-x: auto; padding: 12px; border-radius: 8px; background: var(--code-background); }
    table { border-collapse: collapse; display: block; overflow-x: auto; }
    td, th { border: 1px solid var(--rule); padding: 4px 8px; }
    hr { border: none; border-top: 1px solid var(--rule); }
    """
}

/// Light and dark colors for the reader document.
public struct ReaderTheme: Sendable, Equatable {
    /// An sRGB color with components from 0 to 1.
    public struct Color: Sendable, Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// A `#RRGGBBAA` hex string; components are clamped, so the output is always safe to embed in CSS.
        var css: String {
            "#" + [red, green, blue, alpha].map { component in
                let value = component.isFinite ? min(max(component, 0), 1) : 0
                return String(format: "%02X", Int((value * 255).rounded()))
            }.joined()
        }
    }

    /// A color for light appearance and one for dark appearance.
    public struct ColorPair: Sendable, Equatable {
        let light: Color
        let dark: Color

        public init(light: Color, dark: Color) {
            self.light = light
            self.dark = dark
        }
    }

    let background: ColorPair
    let text: ColorPair
    let secondaryText: ColorPair
    let link: ColorPair
    let codeBackground: ColorPair
    let border: ColorPair

    public init(background: ColorPair, text: ColorPair, secondaryText: ColorPair,
                link: ColorPair, codeBackground: ColorPair, border: ColorPair) {
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.link = link
        self.codeBackground = codeBackground
        self.border = border
    }

    /// Reader colors resolved from the design system for light and dark appearance.
    public static var designSystem: ReaderTheme {
        ReaderTheme(background: colorPair(pageBackground),
                    text: colorPair(.textPrimary),
                    secondaryText: colorPair(.textSecondary),
                    link: colorPair(.accentTextPrimary),
                    codeBackground: colorPair(codeBackground),
                    border: colorPair(.lines))
    }

#if os(iOS)
    private static let pageBackground = DesignSystemColor.background
    private static let codeBackground = DesignSystemColor.surface
#else
    private static let pageBackground = DesignSystemColor.surfaceCanvas
    private static let codeBackground = DesignSystemColor.surfaceSecondary
#endif

    private static func colorPair(_ designSystemColor: DesignSystemColor) -> ColorPair {
        ColorPair(light: resolve(designSystemColor, dark: false), dark: resolve(designSystemColor, dark: true))
    }
}

#if canImport(UIKit)
private extension ReaderTheme {
    static func resolve(_ designSystemColor: DesignSystemColor, dark: Bool) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let color = UIColor(designSystemColor: designSystemColor).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Color(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#elseif canImport(AppKit)
private extension ReaderTheme {
    static func resolve(_ designSystemColor: DesignSystemColor, dark: Bool) -> Color {
        var resolved: NSColor?
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = NSColor(designSystemColor: designSystemColor).usingColorSpace(.sRGB)
        }
        guard let resolved else { return Color(red: 0, green: 0, blue: 0, alpha: 0) }
        return Color(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent, alpha: resolved.alphaComponent)
    }
}
#endif
