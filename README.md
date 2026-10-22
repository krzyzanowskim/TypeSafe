# TypeSafe Swift SDK

SwiftPM client for the TypeSafe System One API. Client behavior follows the official JavaScript SDK (`@typesafe-ai/sdk`). See the HTTP API at [https://docs.typesafe.ai/](https://docs.typesafe.ai/).

## Install

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/krzyzanowskim/TypeSafe", .upToNextMinor(from: "0.2.0")),
],
```

And link the library product:

```swift
.product(name: "TypeSafe", package: "TypeSafe")
```

Set `TYPESAFE_API_KEY` in the environment, or pass `apiKey` to `Configuration`.

> Warning: an API key shipped inside an iOS or macOS app is visible to the user. Call the API from a server you control, or treat any in-app key as public.

## Quickstart

```swift
import TypeSafe

enum Category: String, CaseIterable, Sendable, ChoiceLabel {
    case billing, technical, other
}

struct TicketQuestions: SystemOneQuestions {
    var category = Choice<Category>("What is this ticket about?")
    var isBilling = Noul("Is this ticket about billing?")
    var urgency = try! Score("How urgent is this ticket?", levels: ["can wait", "this week", "today"])

    struct Answers: Decodable, Sendable {
        var category: Choice<Category>.Answer
        var isBilling: Noul.Answer
        var urgency: Score.Answer
    }
}

let client = try TypeSafeClient()
let result = try await client.systemOne(state: ticket, questions: TicketQuestions())
result.answers.category.choice // Category
result.answers.isBilling.noul
result.answers.urgency.score
```

Question initializers take a `JSONValue`, so string literals work directly. Pass a `String` variable as `.string(text)`.

## Images

Image support is experimental. Opt in by sending the `TypeSafe-Danger-Zone-Images: true` header, for every request or per call through `RequestOptions(headers:)`:

```swift
let client = try TypeSafeClient(Configuration(defaultHeaders: ["TypeSafe-Danger-Zone-Images": "true"]))
```

Create an `ImageAsset` from PNG or JPEG file bytes, or with `ImageAsset(base64Encoded:)`. The API detects the format from the bytes and rejects other formats. Requests with images are sent as `multipart/form-data`, and each image is uploaded once however many times it's used.

Place an image anywhere in `state` or in question content:

```swift
struct Claim: Encodable, Sendable {
    var note: String
    var photo: ImageAsset
}

struct ClaimQuestions: SystemOneQuestions {
    var damaged = Noul("Is the product in `photo` damaged?")

    struct Answers: Decodable, Sendable {
        var damaged: Noul.Answer
    }
}

let photo = try ImageAsset(Data(contentsOf: photoURL))
let result = try await client.systemOne(
    state: Claim(note: "The mug arrived with a chipped rim.", photo: photo),
    questions: ClaimQuestions()
)
```

Interpolate images into question literals, or into a `TextWithAssets`, to write them into text. `TextWithAssets.join` writes a list of them:

```swift
struct ListingQuestions: SystemOneQuestions {
    var sameProduct: Noul

    struct Answers: Decodable, Sendable {
        var sameProduct: Noul.Answer
    }
}

let state: TextWithAssets = "The seller uploaded \(TextWithAssets.join(uploads, separator: ", "))."
let questions = ListingQuestions(sameProduct: Noul("Does \(upload) show the same product as \(catalog)?"))
let result = try await client.systemOne(state: state, questions: questions)
```

Interpolating an image into a plain `String` writes only its reference, and the call throws before sending unless the image is also in `assets`. To reference images from plain strings, such as prompts kept in configuration, pass them in `assets` under names you choose. Use distinct delimiters so names don't match ordinary text. Every name must appear in the request.

```swift
let result = try await client.systemOne(
    state: "A customer returned <delivered>. The catalog photo is <catalog>.",
    questions: MatchQuestions(),
    assets: ["<delivered>": delivered, "<catalog>": catalog]
)
```

### Locate something with `Box`

A `Box` question locates what its instructions describe. The answer's `box` holds the edges as fractions of the image's height (`top`, `bottom`) and width (`left`, `right`). Its `confidence` is `nil` when the API doesn't report one. Use the `jev-preview` model:

```swift
struct DamageQuestions: SystemOneQuestions {
    var damage = Box("The damaged area of the product")

    struct Answers: Decodable, Sendable {
        var damage: Box.Answer
    }
}

let result = try await client.systemOne(state: JSONValue.image(photo), questions: DamageQuestions(), model: "jev-preview")
let edges = result.answers.damage.box
```

## Request compression

The client compresses request bodies of 1 KiB or more with gzip. Smaller bodies are sent uncompressed. Pass `compression: .off` to send every body uncompressed, for example to an API that doesn't accept compressed requests:

```swift
let client = try TypeSafeClient(Configuration(compression: .off))
```

## Develop

```bash
swift test
swift run TypeSafeDemo
```

`TypeSafeDemo` reads `TYPESAFE_API_KEY` and asks noul / choice / score questions about a sample billing ticket.
