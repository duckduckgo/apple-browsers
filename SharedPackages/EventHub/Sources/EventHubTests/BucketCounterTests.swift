import Testing
@testable import EventHub

@Suite("BucketCounter")
struct BucketCounterTests {
    static let buckets: BucketList = [
        OrderedBucket(name: "0", config: BucketConfig(gte: 0, lt: 1)),
        OrderedBucket(name: "1-2", config: BucketConfig(gte: 1, lt: 3)),
        OrderedBucket(name: "3-5", config: BucketConfig(gte: 3, lt: 6)),
        OrderedBucket(name: "6-10", config: BucketConfig(gte: 6, lt: 11)),
        OrderedBucket(name: "11-20", config: BucketConfig(gte: 11, lt: 21)),
        OrderedBucket(name: "21-39", config: BucketConfig(gte: 21, lt: 40)),
        OrderedBucket(name: "40+", config: BucketConfig(gte: 40)),
    ]

    @Test("bucketCount returns matching bucket", arguments: [
        (0, "0"), (1, "1-2"), (2, "1-2"), (3, "3-5"), (15, "11-20"), (40, "40+"), (100, "40+"),
    ])
    func bucketCountReturnsMatchingBucket(count: Int, expected: String) {
        #expect(BucketCounter.bucketCount(count, buckets: Self.buckets) == expected)
    }

    @Test("bucketCount lt bound is exclusive, gte bound is inclusive", arguments: [
        (10, "6-10"), (11, "11-20"),
    ])
    func bucketCountLtIsExclusive(count: Int, expected: String) {
        #expect(BucketCounter.bucketCount(count, buckets: Self.buckets) == expected)
    }

    @Test("bucketCount returns nil when no bucket matches")
    func bucketCountReturnsNilWhenNoBucketMatches() {
        let restricted: BucketList = [OrderedBucket(name: "5-9", config: BucketConfig(gte: 5, lt: 10))]
        #expect(BucketCounter.bucketCount(3, buckets: restricted) == nil)
    }

    @Test("bucketCount returns nil for empty buckets")
    func bucketCountReturnsNilForEmptyBuckets() {
        #expect(BucketCounter.bucketCount(5, buckets: []) == nil)
    }

    @Test("shouldStopCounting returns true at the open-ended bucket", arguments: [40, 100])
    func shouldStopCountingReturnsTrueAtMaxBucket(count: Int) {
        #expect(BucketCounter.shouldStopCounting(count, buckets: Self.buckets))
    }

    @Test("shouldStopCounting returns false while higher buckets exist", arguments: [0, 5, 39])
    func shouldStopCountingReturnsFalseWhenHigherBucketsExist(count: Int) {
        #expect(!BucketCounter.shouldStopCounting(count, buckets: Self.buckets))
    }

    @Test("bucketCount returns the first matching bucket in list order")
    func bucketCountReturnsFirstMatchingBucketInInsertionOrder() {
        // Overlapping ranges: count 7 falls in both buckets; first-match (list order) wins.
        let overlapping: BucketList = [
            OrderedBucket(name: "broad", config: BucketConfig(gte: 0, lt: 100)),
            OrderedBucket(name: "narrow", config: BucketConfig(gte: 5, lt: 10)),
        ]
        #expect(BucketCounter.bucketCount(7, buckets: overlapping) == "broad")
    }
}
