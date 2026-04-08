import XCTest
@testable import DebugServer

final class HTTPResponseTests: XCTestCase {

    // MARK: - Convenience Constructors

    func testWhenJSONResponseCreatedThenContentTypeIsSet() {
        let data = "{\"key\":\"value\"}".data(using: .utf8)!
        let response = HTTPResponse.json(data)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "application/json; charset=utf-8")
        XCTAssertEqual(response.body, data)
    }

    func testWhenHTMLResponseCreatedThenContentTypeIsSet() {
        let response = HTTPResponse.html("<h1>Hi</h1>")

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "text/html; charset=utf-8")
        XCTAssertEqual(String(data: response.body!, encoding: .utf8), "<h1>Hi</h1>")
    }

    func testWhenTextResponseCreatedThenContentTypeIsSet() {
        let response = HTTPResponse.text("hello")

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "text/plain; charset=utf-8")
        XCTAssertEqual(String(data: response.body!, encoding: .utf8), "hello")
    }

    func testWhenEmptyResponseCreatedThenStatusIsNoContent() {
        let response = HTTPResponse.empty()

        XCTAssertEqual(response.status, .noContent)
        XCTAssertNil(response.body)
    }

    func testWhenJSONResponseWithCustomStatusThenStatusIsUsed() {
        let response = HTTPResponse.json(Data(), status: .created)

        XCTAssertEqual(response.status, .created)
    }

    func testWhenHTMLResponseWithCustomStatusThenStatusIsUsed() {
        let response = HTTPResponse.html("<p>Error</p>", status: .badRequest)

        XCTAssertEqual(response.status, .badRequest)
    }
}
