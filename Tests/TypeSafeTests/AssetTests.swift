import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import CZlib
@testable import TypeSafe

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
private let jpegBytes = Data([0xFF, 0xD8, 0xFF, 4, 5, 6])

private let noulResponse = """
{"model":"jev-latest","answers":{"n":{"type":"noul","noul":0.5}},"usage":{"input_tokens":1,"output_tokens":1}}
"""

private struct Part {
    var headers: String
    var body: Data
}

/// Split a `multipart/form-data` request into its parts.
private func multipartParts(_ request: URLRequest) throws -> [Part] {
    let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
    let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
    let body = try #require(request.httpBody)
    let delimiter = Data("--\(boundary)".utf8)
    var parts: [Part] = []
    var rest = body[...]
    while let start = rest.range(of: delimiter) {
        rest = rest[start.upperBound...]
        if rest.starts(with: Data("--".utf8)) { break }
        rest = rest.dropFirst(2)
        let end = try #require(rest.range(of: delimiter))
        let part = rest[..<end.lowerBound].dropLast(2)
        let split = try #require(part.range(of: Data("\r\n\r\n".utf8)))
        parts.append(Part(
            headers: String(decoding: part[..<split.lowerBound], as: UTF8.self),
            body: Data(part[split.upperBound...])
        ))
        rest = rest[end.lowerBound...]
    }
    return parts
}

private func requestJSON(_ parts: [Part]) throws -> [String: Any] {
    let first = try #require(parts.first)
    return try #require(JSONSerialization.jsonObject(with: first.body) as? [String: Any])
}

private func gunzip(_ data: Data) throws -> Data {
    var stream = z_stream()
    #expect(inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
    defer { inflateEnd(&stream) }
    var output = Data(count: 1 << 20)
    var status: Int32 = Z_OK
    data.withUnsafeBytes { input in
        output.withUnsafeMutableBytes { buffer in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(buffer.count)
            status = inflate(&stream, Z_FINISH)
        }
    }
    #expect(status == Z_STREAM_END)
    output.count = Int(stream.total_out)
    return output
}

private func client(_ handler: @escaping @Sendable (URLRequest) throws -> Void, compression: RequestCompression = .gzip) throws -> TypeSafeClient {
    try TypeSafeClient(
        Configuration(
            apiKey: "k",
            compression: compression,
            transport: MockTransport { request in
                try handler(request)
                return jsonResponse(status: 200, body: noulResponse)
            }
        ),
        environment: [:]
    )
}

private struct NoulQuestion: SystemOneQuestions {
    var n: Noul
    struct Answers: Decodable, Sendable { var n: Noul.Answer }
}

struct AssetTests {
    @Test func imageInStateIsUploadedAsPart() async throws {
        let photo = try ImageAsset(pngBytes)
        struct Claim: Encodable, Sendable {
            var note: String
            var photo: ImageAsset
        }
        let parts = Box<[Part]>([])
        let client = try client { parts.value = try multipartParts($0) }

        _ = try await client.systemOne(
            state: Claim(note: "chipped rim", photo: photo),
            questions: NoulQuestion(n: Noul("Is the mug damaged?"))
        )

        #expect(parts.value.count == 2)
        let json = try requestJSON(parts.value)
        #expect((json["state"] as? [String: Any])?["photo"] as? String == photo.reference)
        let assets = try #require(json["assets"] as? [String: [String: String]])
        #expect(assets == [photo.reference: ["type": "image", "part": "asset-0"]])
        #expect(parts.value[0].headers.contains("name=\"request\""))
        #expect(parts.value[0].headers.contains("Content-Type: application/json"))
        #expect(parts.value[1].headers.contains("name=\"asset-0\"; filename=\"asset-0\""))
        #expect(parts.value[1].headers.contains("Content-Type: image/png"))
        #expect(parts.value[1].body == pngBytes)
    }

    @Test func interpolatedImagesAreSentOnce() async throws {
        let upload = try ImageAsset(jpegBytes)
        let catalog = try ImageAsset(pngBytes)
        let parts = Box<[Part]>([])
        let client = try client { parts.value = try multipartParts($0) }

        let state: TextWithAssets = "A seller uploaded \(upload) for a listing shown in \(catalog)."
        _ = try await client.systemOne(
            state: state,
            questions: NoulQuestion(n: Noul("Does \(upload) show the same product as \(catalog)?"))
        )

        let json = try requestJSON(parts.value)
        #expect(json["state"] as? String == "A seller uploaded \(upload.reference) for a listing shown in \(catalog.reference).")
        let instructions = ((json["questions"] as? [String: Any])?["n"] as? [String: Any])?["instructions"] as? String
        #expect(instructions == "Does \(upload.reference) show the same product as \(catalog.reference)?")
        let assets = try #require(json["assets"] as? [String: [String: String]])
        #expect(assets[upload.reference]?["part"] == "asset-0")
        #expect(assets[catalog.reference]?["part"] == "asset-1")
        #expect(parts.value.count == 3)
        #expect(parts.value[1].headers.contains("image/jpeg"))
    }

    @Test func namedAssetsReplaceReferences() async throws {
        let photo = try ImageAsset(pngBytes)
        let parts = Box<[Part]>([])
        let client = try client { parts.value = try multipartParts($0) }

        _ = try await client.systemOne(
            state: ["returned": JSONValue.image(photo)],
            questions: NoulQuestion(n: Noul("Is \(photo) the product in the catalog?")),
            assets: ["<returned>": photo]
        )

        let json = try requestJSON(parts.value)
        #expect((json["state"] as? [String: Any])?["returned"] as? String == "<returned>")
        let instructions = ((json["questions"] as? [String: Any])?["n"] as? [String: Any])?["instructions"] as? String
        #expect(instructions == "Is <returned> the product in the catalog?")
        #expect(json["assets"] as? [String: [String: String]] == ["<returned>": ["type": "image", "part": "asset-0"]])
    }

    @Test func namedAssetInPlainStringIsWrittenAsName() async throws {
        let photo = try ImageAsset(pngBytes)
        let parts = Box<[Part]>([])
        let client = try client { parts.value = try multipartParts($0) }

        let text: String = "Look at \(photo)"
        _ = try await client.systemOne(
            state: text,
            questions: NoulQuestion(n: Noul("n?")),
            assets: ["<photo>": photo]
        )

        let json = try requestJSON(parts.value)
        #expect(json["state"] as? String == "Look at <photo>")
        #expect(json["assets"] as? [String: [String: String]] == ["<photo>": ["type": "image", "part": "asset-0"]])
        #expect(parts.value.count == 2)
    }

    @Test func imageUnderTwoNamesIsWrittenAsFirstName() async throws {
        let photo = try ImageAsset(pngBytes)
        let parts = Box<[Part]>([])
        let client = try client { parts.value = try multipartParts($0) }

        _ = try await client.systemOne(
            state: ["photo": JSONValue.image(photo), "note": "Compare with <b>."],
            questions: NoulQuestion(n: Noul("Look at \(photo).")),
            assets: ["<b>": photo, "<a>": photo]
        )

        let json = try requestJSON(parts.value)
        #expect((json["state"] as? [String: Any])?["photo"] as? String == "<a>")
        let instructions = ((json["questions"] as? [String: Any])?["n"] as? [String: Any])?["instructions"] as? String
        #expect(instructions == "Look at <a>.")
    }

    @Test func unreferencedNameThrowsBeforeNetwork() async throws {
        let client = try client { _ in Issue.record("network should not be called") }
        let error = try await #require(throws: TypeSafeError.self) {
            try await client.systemOne(
                state: "no reference here",
                questions: NoulQuestion(n: Noul("n?")),
                assets: ["<photo>": try ImageAsset(pngBytes)]
            )
        }
        #expect(error == .unreferencedAssets(["<photo>"]))
    }

    @Test func imageInPlainStringThrowsBeforeNetwork() async throws {
        let photo = try ImageAsset(pngBytes)
        let client = try client { _ in Issue.record("network should not be called") }
        let text: String = "Look at \(photo)"
        let error = try await #require(throws: TypeSafeError.self) {
            try await client.systemOne(state: text, questions: NoulQuestion(n: Noul("n?")))
        }
        #expect(error == .unattachedImages([photo.reference]))
    }

    @Test func requestsWithoutImagesStayJSON() async throws {
        let contentType = Box<String?>(nil)
        let client = try client { contentType.value = $0.value(forHTTPHeaderField: "Content-Type") }
        _ = try await client.systemOne(state: "x", questions: NoulQuestion(n: Noul("n?")))
        #expect(contentType.value == "application/json")
    }

    @Test func imageValidation() throws {
        #expect(throws: TypeSafeError.emptyImage) { try ImageAsset(Data()) }
        #expect(throws: TypeSafeError.invalidImageBase64) { try ImageAsset(base64Encoded: "not base64!") }
        #expect(try ImageAsset(base64Encoded: pngBytes.base64EncodedString()).data == pngBytes)
        #expect(try ImageAsset(pngBytes) != ImageAsset(pngBytes))
    }

    @Test func joinSendsEveryImage() throws {
        let first = try ImageAsset(pngBytes)
        let second = try ImageAsset(jpegBytes)
        let joined = TextWithAssets.join([first, second], separator: ", ")
        #expect(joined.text == "\(first.reference), \(second.reference)")
        #expect(joined.assets == [first, second])

        let nested: TextWithAssets = "The seller uploaded \(joined)."
        #expect(nested.assets == [first, second])
    }
}

struct BoxTests {
    @Test func encodesTypeAndInstructions() throws {
        let json = try #require(encodeJSON(TypeSafe.Box("The dog")) as? [String: Any])
        #expect(json["type"] as? String == "box")
        #expect(json["instructions"] as? String == "The dog")
        #expect(json["criteria"] == nil)
    }

    @Test func decodesNullConfidence() throws {
        let answer = try decodeJSON(
            #"{"type":"box","box":{"top":0.2,"bottom":0.66,"left":0.19,"right":0.68},"confidence":null}"#,
            as: TypeSafe.Box.Answer.self
        )
        #expect(answer.box == TypeSafe.Box.Coordinates(top: 0.2, bottom: 0.66, left: 0.19, right: 0.68))
        #expect(answer.confidence == nil)
    }
}

struct CompressionTests {
    @Test func gzipsLargeBodies() async throws {
        let saw = Box<URLRequest?>(nil)
        let client = try client { saw.value = $0 }
        let state = String(repeating: "charged twice. ", count: 200)
        _ = try await client.systemOne(state: state, questions: NoulQuestion(n: Noul("n?")))

        let request = try #require(saw.value)
        #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let compressed = try #require(request.httpBody)
        let body = try gunzip(compressed)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["state"] as? String == state)
    }

    @Test func smallBodiesAndOffAreUncompressed() async throws {
        let encodings = Box<[String?]>([])
        let gzipClient = try client { encodings.value.append($0.value(forHTTPHeaderField: "Content-Encoding")) }
        _ = try await gzipClient.systemOne(state: "x", questions: NoulQuestion(n: Noul("n?")))

        let offClient = try client({ encodings.value.append($0.value(forHTTPHeaderField: "Content-Encoding")) }, compression: .off)
        _ = try await offClient.systemOne(
            state: String(repeating: "a", count: 4096),
            questions: NoulQuestion(n: Noul("n?"))
        )
        #expect(encodings.value == [nil, nil])
    }

    @Test func userCannotSetContentEncoding() async throws {
        let encoding = Box<String?>("unset")
        let client = try TypeSafeClient(
            Configuration(
                apiKey: "k",
                defaultHeaders: ["content-encoding": "br"],
                transport: MockTransport { request in
                    encoding.value = request.value(forHTTPHeaderField: "Content-Encoding")
                    return jsonResponse(status: 200, body: noulResponse)
                }
            ),
            environment: [:]
        )
        _ = try await client.systemOne(state: "x", questions: NoulQuestion(n: Noul("n?")))
        #expect(encoding.value == nil)
    }
}
