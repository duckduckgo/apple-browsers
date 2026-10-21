#import <XCTest/XCTest.h>
@interface GateTests : XCTestCase @end
@implementation GateTests
- (void)testCanLaunchAndInspectApplication {
 XCUIApplication *app=[XCUIApplication new]; [app launch];
 XCTAssertTrue([app.staticTexts[@"gate-label"] waitForExistenceWithTimeout:10]);
 [app.staticTexts[@"gate-label"] click];
 XCTAssertEqualObjects(app.staticTexts[@"gate-label"].value, @"Automation is running");
 [app terminate];
}
@end
