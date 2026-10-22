import Foundation

/// A PNG or JPEG image sent with a `systemOne` request.
///
/// Place it in `state` or in question content, interpolate it into a ``TextWithAssets`` or
/// ``JSONValue`` string literal, or pass it in `assets` to reference it by a name you choose.
/// Wherever it appears it is written as ``reference``, and its bytes are uploaded once.
///
/// The API detects the format from the bytes and rejects anything that isn't PNG or JPEG.
/// Requests with images must send the `TypeSafe-Danger-Zone-Images: true` header.
public struct ImageAsset: Sendable, Hashable, Encodable, CustomStringConvertible {
    /// The image file bytes.
    public let data: Data
    /// The unique reference this image is sent under, for referencing it inside text.
    public let reference: String

    public var description: String { reference }

    /// - Throws: ``TypeSafeError/emptyImage`` when `data` is empty.
    public init(_ data: Data) throws {
        guard !data.isEmpty else {
            throw TypeSafeError.emptyImage
        }
        self.data = data
        self.reference = "<image:\(randomHex())>"
    }

    /// Create an image from base64-encoded file bytes, without a `data:` URL prefix.
    public init(base64Encoded text: String) throws {
        guard let data = Data(base64Encoded: text) else {
            throw TypeSafeError.invalidImageBase64
        }
        try self.init(data)
    }

    public static func == (lhs: ImageAsset, rhs: ImageAsset) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(AssetCollector.from(encoder)?.write(self) ?? reference)
    }
}

/// Text with images interpolated into it, so the images are sent with the text.
///
/// ```swift
/// let state: TextWithAssets = "Compare \(photo) with the listing."
/// ```
///
/// Each image is written as its ``ImageAsset/reference``. Interpolating an image into a plain
/// `String` writes only the reference, and the request fails unless the image is attached
/// some other way.
public struct TextWithAssets: Sendable, Hashable, Encodable, CustomStringConvertible, ExpressibleByStringInterpolation {
    /// The text, with each image replaced by its reference.
    public let text: String
    /// The images interpolated into the text, including those in nested `TextWithAssets`.
    public let assets: [ImageAsset]

    public var description: String { text }

    public init(text: String, assets: [ImageAsset]) {
        self.text = text
        self.assets = assets
    }

    public init(stringLiteral value: String) {
        self.init(text: value, assets: [])
    }

    public init(stringInterpolation: StringInterpolation) {
        self.init(text: stringInterpolation.text, assets: stringInterpolation.assets)
    }

    /// Join images with `separator`, sending them with the text.
    public static func join(_ images: some Sequence<ImageAsset>, separator: String = ",") -> TextWithAssets {
        join(images.map { TextWithAssets(text: $0.reference, assets: [$0]) }, separator: separator)
    }

    /// Join texts with `separator`, sending the images in each with the result.
    public static func join(_ texts: some Sequence<TextWithAssets>, separator: String = ",") -> TextWithAssets {
        var interpolation = StringInterpolation(literalCapacity: 0, interpolationCount: 0)
        for (index, text) in texts.enumerated() {
            if index > 0 {
                interpolation.appendLiteral(separator)
            }
            interpolation.appendInterpolation(text)
        }
        return TextWithAssets(stringInterpolation: interpolation)
    }

    public func encode(to encoder: Encoder) throws {
        var text = text
        if let collector = AssetCollector.from(encoder) {
            for asset in assets {
                let written = collector.write(asset)
                if written != asset.reference {
                    text = text.replacingOccurrences(of: asset.reference, with: written)
                }
            }
        }
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var text = ""
        var assets: [ImageAsset] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
        }

        public mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        public mutating func appendInterpolation(_ image: ImageAsset) {
            text += image.reference
            add(image)
        }

        public mutating func appendInterpolation(_ other: TextWithAssets) {
            text += other.text
            other.assets.forEach { add($0) }
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            text += String(describing: value)
        }

        private mutating func add(_ image: ImageAsset) {
            if !assets.contains(image) {
                assets.append(image)
            }
        }
    }
}

/// The JSON request body and the images it references, in the order they are uploaded.
struct EncodedRequest {
    var json: Data
    var assets: [(name: String, image: ImageAsset)]
}

/// Encode `body`, writing each image as its name in `named`, or else as its reference.
///
/// - Throws: ``TypeSafeError`` when a name in `named` doesn't appear in the JSON, or the JSON
///   holds the reference of an image that isn't attached to the request.
func encodeRequest(_ body: some Encodable, assets named: [String: ImageAsset]) throws -> EncodedRequest {
    let collector = AssetCollector(names: named)
    let encoder = JSONEncoder()
    // Unescaped slashes keep names and references findable as plain substrings of the JSON.
    encoder.outputFormatting = [.withoutEscapingSlashes]
    encoder.userInfo[AssetCollector.key] = collector
    var text = String(decoding: try encoder.encode(body), as: UTF8.self)
    // A named image interpolated into a plain String is written as its reference. Sorted, so
    // an image under several names is written as the first, as the collector writes it.
    for (name, image) in named.sorted(by: { $0.key < $1.key }) {
        text = text.replacingOccurrences(of: image.reference, with: jsonEscaped(name))
    }
    let json = Data(text.utf8)

    let unreferenced = named.keys.sorted().filter { !text.contains(jsonEscaped($0)) }
    if !unreferenced.isEmpty {
        throw TypeSafeError.unreferencedAssets(unreferenced)
    }

    var assets = named.sorted { $0.key < $1.key }.map { (name: $0.key, image: $0.value) }
    var sent = Set(named.keys)
    var missing: [String] = []
    for match in text.matches(of: /<image:[0-9a-f]{32}>/) {
        let reference = String(match.output)
        guard !sent.contains(reference) else { continue }
        if let image = collector.found(reference) {
            assets.append((reference, image))
            sent.insert(reference)
        } else if !missing.contains(reference) {
            missing.append(reference)
        }
    }
    if !missing.isEmpty {
        throw TypeSafeError.unattachedImages(missing)
    }
    return EncodedRequest(json: json, assets: assets)
}

/// A `multipart/form-data` body (RFC 7578) whose first part, `request`, is the JSON request
/// with an `assets` map naming the part that holds each image.
func multipartBody(_ request: EncodedRequest) throws -> (content: Data, contentType: String, payload: Data) {
    var entries: [String: [String: String]] = [:]
    for (index, asset) in request.assets.enumerated() {
        entries[asset.name] = ["type": "image", "part": "asset-\(index)"]
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let assetsJSON = try encoder.encode(entries)
    // The request encodes as a compact JSON object, so `assets` goes in before its closing brace.
    guard request.json.last == UInt8(ascii: "}"), request.json.count > 2 else {
        throw TypeSafeError(message: "The request body isn't a JSON object.")
    }
    var payload = request.json.dropLast()
    payload.append(contentsOf: Data(#","assets":"#.utf8) + assetsJSON + Data("}".utf8))

    let boundary = randomHex()
    var content = Data()
    func appendPart(name: String, filename: String?, contentType: String, body: Data) {
        let disposition = filename.map { "name=\"\(name)\"; filename=\"\($0)\"" } ?? "name=\"\(name)\""
        content.append(Data("--\(boundary)\r\nContent-Disposition: form-data; \(disposition)\r\n".utf8))
        content.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        content.append(body)
        content.append(Data("\r\n".utf8))
    }
    appendPart(name: "request", filename: nil, contentType: "application/json", body: Data(payload))
    for (index, asset) in request.assets.enumerated() {
        let name = "asset-\(index)"
        appendPart(name: name, filename: name, contentType: imageContentType(asset.image.data), body: asset.image.data)
    }
    content.append(Data("--\(boundary)--\r\n".utf8))
    return (content, "multipart/form-data; boundary=\(boundary)", Data(payload))
}

/// Collects the images written while encoding a request, keyed by reference.
final class AssetCollector: @unchecked Sendable {
    static let key = CodingUserInfoKey(rawValue: "ai.typesafe.assets")!

    private let lock = NSLock()
    private let names: [String: String]
    private var images: [String: ImageAsset] = [:]

    init(names named: [String: ImageAsset]) {
        self.names = Dictionary(named.map { ($0.value.reference, $0.key) }, uniquingKeysWith: min)
    }

    static func from(_ encoder: Encoder) -> AssetCollector? {
        encoder.userInfo[key] as? AssetCollector
    }

    /// Record `image` and return the text it is written as: its name, or else its reference.
    func write(_ image: ImageAsset) -> String {
        if let name = names[image.reference] {
            return name
        }
        lock.lock()
        defer { lock.unlock() }
        images[image.reference] = image
        return image.reference
    }

    func found(_ reference: String) -> ImageAsset? {
        lock.lock()
        defer { lock.unlock() }
        return images[reference]
    }
}

/// `value` as it appears inside a JSON string, without the surrounding quotes.
private func jsonEscaped(_ value: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { return value }
    return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
}

/// The content type whose file signature `data` starts with, or `application/octet-stream`.
private func imageContentType(_ data: Data) -> String {
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        return "image/png"
    }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) {
        return "image/jpeg"
    }
    return "application/octet-stream"
}

/// 32 random lowercase hex digits.
private func randomHex() -> String {
    var generator = SystemRandomNumberGenerator()
    return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
}
