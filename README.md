# TypeSafe Swift SDK

SwiftPM client for the TypeSafe System One API. Client behavior follows the official JavaScript SDK (`@typesafe-ai/sdk`). See the HTTP API at [https://docs.typesafe.ai/](https://docs.typesafe.ai/).

## Install

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/krzyzanowskim/TypeSafe", .upToNextMinor(from: "0.1.0")),
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

## Develop

```bash
swift test
swift run TypeSafeDemo
```

`TypeSafeDemo` reads `TYPESAFE_API_KEY` and asks noul / choice / score questions about a sample billing ticket.
