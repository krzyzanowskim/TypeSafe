import Foundation
import Testing
@testable import TypeSafe

struct JSONValueTests {
    @Test func encodesPrimitivesAsJSON() throws {
        #expect(try encodeJSON(JSONValue.string("hi")) as? String == "hi")
        #expect(try encodeJSON(JSONValue.number(3)) as? Double == 3)
        #expect(try encodeJSON(JSONValue.bool(true)) as? Bool == true)
        #expect(try encodeJSON(JSONValue.null) is NSNull)
    }

    @Test func encodesObjectAndArray() throws {
        let value: JSONValue = ["document": "hello", "tags": ["a", "b"]]
        let object = try #require(encodeJSON(value) as? [String: Any])
        #expect(object["document"] as? String == "hello")
        #expect(object["tags"] as? [String] == ["a", "b"])
    }

    @Test func decodesRoundTrip() throws {
        let json = "{\"ok\":true,\"n\":1.5,\"s\":\"x\",\"a\":[null],\"z\":null}"
        let value = try decodeJSON(json, as: JSONValue.self)
        let encoded = try encodeJSON(value)
        let object = try #require(encoded as? [String: Any])
        #expect(object["ok"] as? Bool == true)
        #expect(object["n"] as? Double == 1.5)
        #expect(object["s"] as? String == "x")
        #expect(object["z"] is NSNull)
    }

    @Test func integerLiteralIsNumber() {
        let value: JSONValue = 4
        #expect(value == .number(4))
    }
}
