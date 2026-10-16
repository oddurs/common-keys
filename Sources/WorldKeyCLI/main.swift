import Foundation
import WorldKey

/// The engine from the command line, for scripts and other input tools: list keyboards, read keys
/// on any of them, convert text typed on the wrong one, and measure how well detection works.

let usage = """
    usage: worldkey <command> [options]

      sources [--all]                         keyboards enabled on this Mac (--all: every installed one)
      convert <text> --from <kb> [--to <kb>]  what text typed on <kb> was meant to say on another keyboard
      detect <text> --from <kb>               whether text was typed on the wrong keyboard, among enabled ones
      eval [--keyboards a,b,…] [--words N]    accuracy on dictionary words typed on the right and wrong keyboard
           [--engine rules|model] [--split all|train|heldOut]
      train [--words N] [--write path]        fit the combiner's weights on synthetic examples

    Keyboards are named by id (com.apple.keylayout.US) or its last part (US, Icelandic, 2SetKorean).
    Add --json for machine-readable output.
    """

struct Failure: Error, CustomStringConvertible {
    var description: String
}

var arguments = Array(CommandLine.arguments.dropFirst())
let json = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }

@MainActor
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

/// The user's keyboards, read before anything lists every installed source; see `installed()`.
let enabled = InputSources.enabled()

@MainActor
func keyboard(_ name: String) throws -> any Keyboard {
    if let exact = InputSources.keyboard(name) { return exact }
    let all = enabled + InputSources.installed()
    let lowered = name.lowercased()
    guard
        let match = all.first(where: { $0.id.split(separator: ".").last?.lowercased() == lowered })
            ?? all.first(where: { $0.name.lowercased() == lowered })
    else { throw Failure(description: "no keyboard named \(name); see `worldkey sources --all`") }
    return match
}

/// The pairs the combiner is fitted on and gated against.
let trainingPairs = [
    "Icelandic", "Russian", "2SetKorean", "Greek", "Hebrew", "Arabic", "French", "German",
    // Languages macOS has no dictionary for, with shipped word lists.
    "Thai", "Georgian-QWERTY", "Armenian-HMQWERTY",
].map {
    ["US", $0]
}

@MainActor
func detector(_ engine: String?) throws -> Detector {
    switch engine {
    case nil, "model": Detector(weights: .trained)
    case "rules": Detector(weights: .hand)
    case let other?: throw Failure(description: "unknown engine \(other); use rules or model")
    }
}

@MainActor
func emit(_ value: some Encodable, text: () -> String) throws {
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    } else {
        print(text())
    }
}

struct Source: Encodable {
    var id, name, language, kind, flag: String
}

struct Reading: Encodable {
    var keyboard: String
    var text: String
    var gain: Double?
}

@MainActor
func run() throws {
    guard let command = arguments.first else { throw Failure(description: usage) }
    let lexicon = SystemLexicon()

    switch command {
    case "sources":
        let sources = (arguments.contains("--all") ? InputSources.installed() : enabled).map {
            Source(id: $0.id, name: $0.name, language: $0.language, kind: $0.kind.rawValue, flag: $0.flag)
        }
        try emit(sources) {
            sources.map { "\($0.flag)\t\($0.kind)\t\($0.language)\t\($0.id)\t\($0.name)" }.joined(
                separator: "\n")
        }

    case "convert", "detect":
        guard arguments.count > 1, let fromName = option("--from") else { throw Failure(description: usage) }
        let text = arguments[1]
        let from = try keyboard(fromName)
        guard let strokes = from.strokes(for: text) else {
            throw Failure(description: "\(from.name) cannot type “\(text)”")
        }
        let candidates = [from] + enabled.filter { $0.id != from.id }
        let detector = Detector()
        if command == "convert" {
            let readings: [Reading]
            if let toName = option("--to") {
                let to = try keyboard(toName)
                readings = [Reading(keyboard: to.id, text: to.text(for: strokes), gain: nil)]
            } else {
                readings = detector.alternatives(
                    strokes, typedIn: from, candidates: candidates, memory: Memory(), lexicon: lexicon
                ).map { Reading(keyboard: $0.targetID, text: $0.replacement, gain: $0.gain) }
            }
            try emit(readings) {
                readings.map {
                    "\($0.text)\t\($0.keyboard)" + ($0.gain.map { String(format: "\t%+.1f", $0) } ?? "")
                }
                .joined(separator: "\n")
            }
        } else {
            let decision = detector.decide(
                strokes, typedIn: from, candidates: candidates, memory: Memory(), lexicon: lexicon)
            let reading = decision.map { Reading(keyboard: $0.targetID, text: $0.replacement, gain: $0.gain) }
            try emit(reading) {
                reading.map { "\($0.text)\t\($0.keyboard)" } ?? "\(text)\t(typed on the right keyboard)"
            }
        }

    case "eval":
        let names = option("--keyboards")?.split(separator: ",").map(String.init)
        let keyboards = try names?.map(keyboard) ?? enabled
        let count = Int(option("--words") ?? "") ?? 200
        let split =
            try option("--split").map { name in
                guard let split = Split(rawValue: name) else { throw Failure(description: "unknown split \(name)") }
                return split
            } ?? .all
        let report = Evaluation.run(
            keyboards, words: count, lexicon: lexicon, detector: try detector(option("--engine")), split: split)
        try emit(report) { report.table }

    case "train":
        let count = Int(option("--words") ?? "") ?? 400
        let sets = try trainingPairs.map { pair in try pair.map(keyboard) }
        let examples = Training.examples(sets, words: count, split: .train, lexicon: lexicon)
        let weights = Training.fit(examples)
        let positives = examples.filter(\.meant).count
        let note =
            "Fitted on \(examples.count) examples (\(positives) to fix, \(examples.count - positives) to leave), "
            + "\(count) training words per language, U.S. paired with \(trainingPairs.map { $0[1] }.joined(separator: ", "))."
        if let path = option("--write") {
            try Training.source(weights, note: note).write(toFile: path, atomically: true, encoding: .utf8)
        }
        try emit(weights) {
            ([note, String(format: "threshold %.4f", weights.threshold)]
                + Feature.allCases.map { String(format: "  %-20@ %+.4f", $0.rawValue, weights.values[$0] ?? 0) })
                .joined(separator: "\n")
        }

    default:
        throw Failure(description: usage)
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
