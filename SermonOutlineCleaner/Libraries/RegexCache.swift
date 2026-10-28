import Foundation
import os

//
//  RegexCache.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

/// Thread-safe precompiled regular expression cache and pattern matching utilities.
nonisolated enum RegexCache {

    private struct CacheKey: Hashable, Sendable {
        let pattern: String
        let optionsRawValue: UInt
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [CacheKey: NSRegularExpression]())

    static func compiled(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = CacheKey(pattern: pattern, optionsRawValue: options.rawValue)
        if let existing = cache.withLock({ $0[key] }) {
            return existing
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        cache.withLock { $0[key] = regex }
        return regex
    }

    static func replace(
        _ text: String,
        pattern: String,
        template: String,
        caseInsensitive: Bool = false
    ) -> String {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let rx = compiled(pattern: pattern, options: opts) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return rx.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    static func matches(
        _ text: String,
        pattern: String,
        caseInsensitive: Bool = true
    ) -> [[String]] {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let rx = compiled(pattern: pattern, options: opts) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return rx.matches(in: text, options: [], range: nsRange).map { match in
            (0..<match.numberOfRanges).map { idx in
                let r = match.range(at: idx)
                guard r.location != NSNotFound, let range = Range(r, in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    static func firstMatch(
        _ text: String,
        pattern: String,
        caseInsensitive: Bool = true
    ) -> [String]? {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let rx = compiled(pattern: pattern, options: opts) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = rx.firstMatch(in: text, options: [], range: nsRange) else { return nil }
        return (0..<match.numberOfRanges).map { idx in
            let r = match.range(at: idx)
            guard r.location != NSNotFound, let range = Range(r, in: text) else { return "" }
            return String(text[range])
        }
    }
}
