import Foundation
import os.log

/// Protocol for caching DaxEasterEgg logos
protocol DaxEasterEggLogoCaching {
    /// Store a logo URL for the given search query
    func storeLogo(_ logoURL: String, for searchQuery: String)
    
    /// Retrieve a cached logo URL for the given search query
    func getLogo(for searchQuery: String) -> String?
}

/// In-memory cache for DaxEasterEgg logos, mapping search queries to logo URLs.
final class DaxEasterEggLogoCache: DaxEasterEggLogoCaching {
    
    // MARK: - Properties
    
    /// Thread-safe cache storage: searchQuery (lowercased) → logoURL (absolute)
    private var logoCache: [String: String] = [:]
    private let cacheQueue = DispatchQueue(label: "dax-easter-egg-logo-cache", attributes: .concurrent)
    private let maxCacheSize = 100 // Prevent memory bloat
    
    init() {}
    
    // MARK: - Public Methods
    
    /// Store a logo URL for the given search query
    /// - Parameters:
    ///   - logoURL: The processed, absolute logo URL
    ///   - searchQuery: The raw search query from the URL
    func storeLogo(_ logoURL: String, for searchQuery: String) {
        let normalizedQuery = normalize(query: searchQuery)
        
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Simple size management - clear cache if it gets too large
            if self.logoCache.count >= self.maxCacheSize {
                self.logoCache.removeAll()
                Logger.daxEasterEgg.debug("DaxEasterEggLogoCache: Cache cleared due to size limit")
            }
            
            self.logoCache[normalizedQuery] = logoURL
            Logger.daxEasterEgg.debug("DaxEasterEggLogoCache: Stored logo for query '\(normalizedQuery)' -> \(logoURL)")
        }
    }
    
    /// Retrieve a cached logo URL for the given search query
    /// - Parameter searchQuery: The raw search query from the URL
    /// - Returns: The cached logo URL if found, nil otherwise
    func getLogo(for searchQuery: String) -> String? {
        let normalizedQuery = normalize(query: searchQuery)
        
        return cacheQueue.sync {
            let logoURL = logoCache[normalizedQuery]
            if let logoURL = logoURL {
                Logger.daxEasterEgg.debug("DaxEasterEggLogoCache: Cache HIT for query '\(normalizedQuery)' -> \(logoURL)")
            } else {
                Logger.daxEasterEgg.debug("DaxEasterEggLogoCache: Cache MISS for query '\(normalizedQuery)'")
            }
            return logoURL
        }
    }
    
    // MARK: - Private Methods
    
    /// Normalize search query for consistent cache keys
    /// - Parameter query: Raw search query
    /// - Returns: Normalized cache key (lowercased, trimmed)
    private func normalize(query: String) -> String {
        return query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
