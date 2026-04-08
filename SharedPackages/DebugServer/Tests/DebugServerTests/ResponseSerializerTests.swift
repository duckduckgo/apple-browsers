import XCTest
@testable import DebugServer

final class ResponseSerializerTests: XCTestCase {

    private let serializer = ResponseSerializer()

    // MARK: - Status Line

    func testWhenOKResponseThenStatusLineIsCorrect() {
        let response = HTTPResponse(status: .ok)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.hasPrefix("HTTP/1.1 200 OK\r\n"))
    }

    func testWhenNotFoundResponseThenStatusLineIsCorrect() {
        let response = HTTPResponse(status: .notFound)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
    }

    func testWhenInternalServerErrorThenStatusLineIsCorrect() {
        let response = HTTPResponse(status: .internalServerError)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.hasPrefix("HTTP/1.1 500 Internal Server Error\r\n"))
    }

    // MARK: - Headers

    func testWhenCustomHeadersThenTheyAreIncluded() {
        let response = HTTPResponse(
            status: .ok,
            headers: ["X-Custom": "value"]
        )
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("X-Custom: value\r\n"))
    }

    func testWhenNoContentLengthProvidedThenItIsAdded() {
        let body = "Hello".data(using: .utf8)!
        let response = HTTPResponse(status: .ok, body: body)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("Content-Length: 5\r\n"))
    }

    func testWhenContentLengthProvidedThenItIsNotOverridden() {
        let response = HTTPResponse(
            status: .ok,
            headers: ["Content-Length": "99"],
            body: "Hi".data(using: .utf8)
        )
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("Content-Length: 99\r\n"))
        XCTAssertFalse(output.contains("Content-Length: 2\r\n"))
    }

    func testWhenConnectionHeaderNotProvidedThenCloseIsAdded() {
        let response = HTTPResponse(status: .ok)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("Connection: close\r\n"))
    }

    // MARK: - Body

    func testWhenBodyPresentThenItAppearsAfterHeaders() {
        let body = "{\"ok\":true}"
        let response = HTTPResponse(status: .ok, body: body.data(using: .utf8))
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        let parts = output.components(separatedBy: "\r\n\r\n")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[1], body)
    }

    func testWhenNoBodyThenContentLengthIsZero() {
        let response = HTTPResponse(status: .noContent)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("Content-Length: 0\r\n"))
    }
}
