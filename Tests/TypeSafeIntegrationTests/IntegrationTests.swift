import Foundation
import ImageIO
import Testing
import TypeSafe

private let hasAPIKey: Bool = {
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    else { return false }
    return !key.isEmpty
}()

struct IntegrationTests {
    @Test(.enabled(if: hasAPIKey))
    func listsModels() async throws {
        let client = try TypeSafeClient()
        let models = try await client.models.list()
        #expect(!models.isEmpty)
        #expect(models.contains { $0.name.contains("jev") })
    }

    @Test(.enabled(if: hasAPIKey))
    func systemOneNoul() async throws {
        let client = try TypeSafeClient()
        struct Q: SystemOneQuestions {
            var billing = Noul("Is this about billing?")
            struct Answers: Decodable, Sendable {
                var billing: Noul.Answer
            }
        }
        let result = try await client.systemOne(
            state: "I was charged twice. Please refund.",
            questions: Q()
        )
        #expect(result.answers.billing.noul > 0.5)
        #expect(try #require(result.usage.inputTokens) > 0)
    }

    @Test(.enabled(if: hasAPIKey))
    func gzipBodyIsAccepted() async throws {
        let client = try TypeSafeClient()
        struct Q: SystemOneQuestions {
            var billing = Noul("Is this about billing?")
            struct Answers: Decodable, Sendable {
                var billing: Noul.Answer
            }
        }
        let result = try await client.systemOne(
            state: String(repeating: "I was charged twice. Please refund. ", count: 60),
            questions: Q()
        )
        #expect(result.answers.billing.noul > 0.5)
    }

    @Test(.enabled(if: hasAPIKey))
    func boxLocatesRectangleInUploadedImage() async throws {
        let client = try TypeSafeClient(Configuration(defaultHeaders: ["TypeSafe-Danger-Zone-Images": "true"]))
        let photo = try ImageAsset(redRectanglePNG())
        struct Q: SystemOneQuestions {
            var rectangle = TypeSafe.Box("the red rectangle")
            var isRed = Noul("Is there a red shape in the image?")
            struct Answers: Decodable, Sendable {
                var rectangle: TypeSafe.Box.Answer
                var isRed: Noul.Answer
            }
        }
        let result = try await client.systemOne(state: JSONValue.image(photo), questions: Q(), model: "jev-preview")
        let box = result.answers.rectangle.box
        // The rectangle spans 0.25–0.75 of each side.
        #expect(abs(box.left - 0.25) < 0.1)
        #expect(abs(box.right - 0.75) < 0.1)
        #expect(abs(box.top - 0.25) < 0.1)
        #expect(abs(box.bottom - 0.75) < 0.1)
        #expect(result.answers.isRed.noul > 0.5)
    }
}

/// A 400 × 400 white PNG with a red square from 100 to 300 pixels on each axis.
private func redRectanglePNG() throws -> Data {
    let size = 400
    let context = try #require(CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 100, y: 100, width: 200, height: 200))
    let image = try #require(context.makeImage())

    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}
