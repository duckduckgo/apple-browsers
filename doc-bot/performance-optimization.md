---
alwaysApply: false
title: "Performance Optimization Guidelines"
description: "Performance optimization guidelines for DuckDuckGo browser including memory management, UI performance, network optimization, and monitoring"
keywords: ["performance", "optimization", "memory management", "UI performance", "network optimization", "database performance", "monitoring"]
---

# Performance Optimization Guidelines

## Memory Management

### Avoid Retain Cycles
```swift
// Use weak/unowned references appropriately
class ViewController: UIViewController {
    private var timer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Bad - Creates retain cycle
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateUI()
        }
        
        // Good - Weak reference prevents retain cycle
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
```

### Lazy Loading
```swift
class DataManager {
    // Load expensive resources only when needed
    private lazy var database: Database = {
        return Database()
    }()
    
    // Use computed properties for lightweight calculations
    var itemCount: Int {
        return items.count
    }
    
    // Cache expensive computations
    private var _processedData: [ProcessedItem]?
    var processedData: [ProcessedItem] {
        if let cached = _processedData {
            return cached
        }
        let processed = items.map { ProcessedItem($0) }
        _processedData = processed
        return processed
    }
}
```

### Memory-Efficient Collections
```swift
// Use appropriate collection types
struct LargeDataSet {
    // Bad - Loads all data into memory
    var allItems: [Item] {
        return database.fetchAll()
    }
    
    // Good - Use lazy sequences
    var items: LazySequence<[Item]> {
        return database.fetchAll().lazy
    }
    
    // Better - Use pagination
    func items(page: Int, pageSize: Int = 50) -> [Item] {
        return database.fetch(offset: page * pageSize, limit: pageSize)
    }
}
```

## UI Performance

### Main Thread Protection
```swift
class ImageLoader {
    func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        Task {
            // Perform heavy work on background queue
            let data = try? await URLSession.shared.data(from: url).0
            let image = data.flatMap { UIImage(data: $0) }
            
            // Always update UI on main thread
            await MainActor.run {
                completion(image)
            }
        }
    }
}
```

### Efficient Table/Collection Views
```swift
class OptimizedTableViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Register reusable cells
        tableView.register(CustomCell.self, forCellReuseIdentifier: "Cell")
        
        // Set estimated heights for better scrolling
        tableView.estimatedRowHeight = 44.0
        tableView.rowHeight = UITableView.automaticDimension
        
        // Enable prefetching
        tableView.prefetchDataSource = self
    }
    
    // Reuse cells efficiently
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! CustomCell
        
        // Configure cell with minimal work
        cell.configure(with: items[indexPath.row])
        
        // Cancel any ongoing async work
        cell.prepareForReuse()
        
        return cell
    }
}

extension OptimizedTableViewController: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        // Preload data for upcoming cells
        let urls = indexPaths.compactMap { items[$0.row].imageURL }
        ImageCache.shared.preload(urls: urls)
    }
}
```

### Image Optimization
```swift
extension UIImage {
    // Resize images to appropriate size
    func resized(to targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    // Decode images on background queue
    func decodedImage() -> UIImage? {
        guard let cgImage = cgImage else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        guard let decodedImage = context?.makeImage() else { return nil }
        return UIImage(cgImage: decodedImage)
    }
}
```

## Network Performance

### Efficient API Calls
```swift
class APIClient {
    private let session: URLSession
    private let cache = URLCache(
        memoryCapacity: 10 * 1024 * 1024,  // 10 MB
        diskCapacity: 50 * 1024 * 1024,     // 50 MB
        diskPath: nil
    )
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 5
        
        self.session = URLSession(configuration: configuration)
    }
    
    // Batch requests when possible
    func fetchMultipleItems(ids: [String]) async throws -> [Item] {
        // Bad - Multiple individual requests
        // let items = try await ids.asyncMap { try await fetchItem(id: $0) }
        
        // Good - Single batch request
        let request = BatchRequest(ids: ids)
        return try await fetch(request)
    }
    
    // Use compression
    func createRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        return request
    }
}
```

### Download Optimization
```swift
class DownloadManager {
    // Use background sessions for large downloads
    private lazy var backgroundSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.duckduckgo.downloads")
        configuration.isDiscretionary = true
        configuration.sessionSendsLaunchEvents = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    // Resume interrupted downloads
    func resumeDownload(from resumeData: Data) {
        let task = backgroundSession.downloadTask(withResumeData: resumeData)
        task.resume()
    }
    
    // Limit concurrent downloads
    private let downloadQueue = OperationQueue()
    
    init() {
        downloadQueue.maxConcurrentOperationCount = 3
    }
}
```

## Database Performance

### Efficient Queries
```swift
import GRDB

class DatabaseManager {
    // Use indexes for frequently queried columns
    func createIndexes(_ db: Database) throws {
        try db.create(index: "idx_bookmarks_url", on: "bookmarks", columns: ["url"])
        try db.create(index: "idx_history_date", on: "history", columns: ["visitDate"])
    }
    
    // Batch operations
    func insertMultipleItems(_ items: [Item]) throws {
        try dbQueue.write { db in
            // Use transactions for bulk operations
            try items.forEach { item in
                try item.insert(db)
            }
        }
    }
    
    // Use appropriate fetch limits
    func fetchRecentHistory(limit: Int = 100) throws -> [HistoryItem] {
        try dbQueue.read { db in
            try HistoryItem
                .order(Column("visitDate").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    // Optimize complex queries
    func searchBookmarks(query: String) throws -> [Bookmark] {
        try dbQueue.read { db in
            // Use FTS (Full Text Search) for text searching
            let pattern = "%\(query)%"
            return try Bookmark
                .filter(Column("title").like(pattern) || Column("url").like(pattern))
                .limit(50)
                .fetchAll(db)
        }
    }
}
```

## Algorithm Optimization

### Use Efficient Data Structures
```swift
// Choose appropriate data structures
class URLMatcher {
    // Bad - O(n) lookup
    private var blockedURLs: [String] = []
    
    func isBlocked(_ url: String) -> Bool {
        return blockedURLs.contains(url)
    }
    
    // Good - O(1) lookup
    private var blockedURLSet: Set<String> = []
    
    func isBlockedOptimized(_ url: String) -> Bool {
        return blockedURLSet.contains(url)
    }
}
```

### Avoid Expensive Operations
```swift
extension Array {
    // Bad - Creates multiple intermediate arrays
    func processItems() -> [ProcessedItem] {
        return self
            .compactMap { $0 as? Item }
            .filter { $0.isValid }
            .map { ProcessedItem($0) }
            .sorted { $0.priority > $1.priority }
    }
    
    // Good - Use lazy evaluation
    func processItemsOptimized() -> [ProcessedItem] {
        return self.lazy
            .compactMap { $0 as? Item }
            .filter { $0.isValid }
            .map { ProcessedItem($0) }
            .sorted { $0.priority > $1.priority }
    }
}
```

## Monitoring and Profiling

### Performance Metrics
```swift
class PerformanceMonitor {
    static func measure<T>(
        _ title: String,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("⏱ \(title): \(timeElapsed)s")
            
            // Log slow operations
            if timeElapsed > 1.0 {
                Pixel.fire(.performanceWarning(operation: title, duration: timeElapsed))
            }
        }
        return try operation()
    }
}

// Usage
let results = PerformanceMonitor.measure("Database Query") {
    try database.fetchAllBookmarks()
}
```

### Memory Monitoring
```swift
class MemoryMonitor {
    static var currentMemoryUsage: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0
    }
    
    static func logMemoryUsage(_ context: String) {
        let usage = currentMemoryUsage
        print("💾 Memory usage (\(context)): \(usage) MB")
        
        if usage > 200 { // 200 MB threshold
            Pixel.fire(.highMemoryUsage(context: context, usage: usage))
        }
    }
}
```

## Best Practices Summary

1. **Profile First**: Use Instruments to identify actual bottlenecks
2. **Measure Impact**: Quantify performance improvements
3. **Cache Wisely**: Cache expensive computations but watch memory usage
4. **Async Everything**: Keep UI responsive with background processing
5. **Batch Operations**: Combine multiple operations when possible
6. **Lazy Loading**: Load data only when needed
7. **Resource Management**: Release resources promptly
8. **Monitor Production**: Track performance metrics in production