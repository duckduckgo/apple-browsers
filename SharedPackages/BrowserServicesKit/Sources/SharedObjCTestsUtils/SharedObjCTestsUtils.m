#import <XCTest/XCTest.h>
#import <os/log.h>

@interface GlobalTestObserver : NSObject <XCTestObservation>
@property (nonatomic, strong) os_log_t logger;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation GlobalTestObserver

- (instancetype)init {
    self = [super init];
    if (self) {
        self.logger = os_log_create("General", "");
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [self.dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];

        os_log(self.logger, "🟢🟢🟢 Starting");
    }
    return self;
}

- (NSString *)timestampString {
    return [self.dateFormatter stringFromDate:[NSDate date]];
}

- (void)testBundleWillStart:(NSBundle *)testBundle {
}

- (void)testBundleDidFinish:(NSBundle *)testBundle {
}

- (void)testSuiteWillStart:(XCTestSuite *)testSuite {
    if (![testSuite.name hasSuffix:@".xctest"] && ![testSuite.name isEqualToString:@"All tests"]) {
        os_log(self.logger, "Test Suite '%{public}@' started at %{public}@.", testSuite.name, [self timestampString]);
    }
}

- (void)testSuiteDidFinish:(XCTestSuite *)testSuite {
    if (![testSuite.name hasSuffix:@".xctest"] && ![testSuite.name isEqualToString:@"All tests"]) {
        NSString *result = (testSuite.testRun.hasSucceeded) ? @"passed" : @"failed";
        double totalTime = testSuite.testRun.totalDuration;
        double testTime = testSuite.testRun.testDuration;
        
        os_log(self.logger, "🔵 Test Suite '%{public}@' %{public}@ at %{public}@.", testSuite.name, result, [self timestampString]);
        os_log(self.logger, "\t Executed %lu tests, with %lu failures (%lu unexpected) in %.3f (%.3f) seconds",
               (unsigned long)testSuite.testRun.testCaseCount,
               (unsigned long)testSuite.testRun.failureCount,
               (unsigned long)testSuite.testRun.unexpectedExceptionCount,
               testTime,
               totalTime);
    }
}

- (void)testCaseWillStart:(XCTestCase *)testCase {
    os_log(self.logger, "➡️ Test Case '%{public}@' started.", testCase.name);
}

- (void)testCaseDidFinish:(XCTestCase *)testCase {
    NSString *result = (testCase.testRun.hasSucceeded) ? @"passed" : @"failed";
    NSString *marker = (testCase.testRun.hasSucceeded) ? @"🟢" : @"🔴";
    double duration = testCase.testRun.totalDuration;
    
    os_log(self.logger, "%{public}@ Test Case '%{public}@' %{public}@ (%.3f seconds).", marker, testCase.name, result, duration);
}

- (void)testCase:(XCTestCase *)testCase didFailWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber {
    os_log_error(self.logger, "🔴 Test Case '%{public}@' failed: %{public}@ at %{public}@:%lu", 
                 testCase.name, description, filePath.lastPathComponent, (unsigned long)lineNumber);
}

@end

@interface SharedObjCTestsUtils : NSObject 
@end
@implementation SharedObjCTestsUtils

// This method will be called automatically by the Objective-C runtime
// before any test methods are executed
+ (void)load {
    // Add XCTest observer to log test events
    GlobalTestObserver *observer = [[GlobalTestObserver alloc] init];
    [[XCTestObservationCenter sharedTestObservationCenter] addTestObserver:observer];
}

@end 
