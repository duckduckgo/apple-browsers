import XCTest
@testable import DebugServer

final class RouteMatchingTests: XCTestCase {

    private var server: DebugHTTPServer!

    override func setUp() {
        super.setUp()
        server = DebugHTTPServer(port: 0)
    }

    override func tearDown() {
        server.stop()
        server = nil
        super.tearDown()
    }

    // MARK: - Route Registration

    func testWhenRouteRegisteredThenItCanBeAddedWithoutError() {
        server.addRoute("/test", method: .GET) { _ in
            .text("OK")
        }
    }

    func testWhenStaticRouteRegisteredThenItCanBeAddedWithoutError() {
        server.addStaticRoute("/page", htmlString: "<html><body>Hello</body></html>")
    }

    func testWhenMultipleRoutesRegisteredThenAllAreAccepted() {
        server.addRoute("/a", method: .GET) { _ in .text("A") }
        server.addRoute("/b", method: .POST) { _ in .text("B") }
        server.addRoute("/c", method: .DELETE) { _ in .empty() }
    }

    func testWhenSamePathDifferentMethodsThenBothAreRegistered() {
        server.addRoute("/resource", method: .GET) { _ in .text("get") }
        server.addRoute("/resource", method: .POST) { _ in .text("post") }
    }
}
