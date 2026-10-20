# The understand step on a sample thought (2026-10-20)

A first look at what Apple's on-device model returns for the `concepts@1` and `summary@1` prompts ([ADR 0012](../decisions/0012-concepts-and-summaries.md)). Three runs on one made-up thought. This is a spot check, not an evaluation.

## Setup

- Model: Apple Foundation Models (`SystemLanguageModel.default`), macOS 26, temperature 0.2, a fresh session per request. Same settings as `apple-foundation-system` in `Seeds/models.json`.
- Prompts: the `concepts` and `summary` templates from `Seeds/prompts.json`, unchanged, with `{{text}}` filled in.
- Schema: the same guided-generation schema `GenerationSchemaBuilder` builds from each prompt's `output_schema`.
- Run as a standalone Swift program outside the app (code at the end), so the app's pipeline and database were not involved. Character positions below were computed the way `ConceptMentions.locate` does it: whole words, any case, UTF-16 offsets.

## Input

64 words, so the summary runs too (`summary.min_words` is 40). The text is one paragraph of 388 characters, so it becomes one passage.

> Heute Morgen wieder kaum geschlafen, weil die Heizung in der Wohnung die ganze Nacht geklackert hat. Ich habe dann mit Marleen telefoniert, sie ist gerade in Lissabon für die Konferenz. Sie meinte, ich soll endlich den Vermieter anrufen. Eigentlich bin ich eher müde als genervt. Im Büro hat mein Chef nach dem Release gefragt, und ich hatte keine Antwort, weil das Deployment noch hängt.

## Output

Concepts (field order varies between runs and is shown normalised):

| run | person | place | topic | emotion |
|---|---|---|---|---|
| 1 | Marleen | Lissabon | Heizung, Vermieter | müde |
| 2 | Marleen | Lissabon | Heizung, Vermieter, **Job** | none |
| 3 | Marleen | Lissabon | Heizung, Vermieter | müde |

Run 1 raw:

```json
{"concepts": [
  {"name": "Marleen",   "kind": "person",  "mention": "Marleen"},
  {"name": "Lissabon",  "kind": "place",   "mention": "Lissabon"},
  {"name": "Heizung",   "kind": "topic",   "mention": "Heizung"},
  {"name": "Vermieter", "kind": "topic",   "mention": "Vermieter"},
  {"name": "müde",      "kind": "emotion", "mention": "müde"}
]}
```

Where tällmi finds the words (UTF-16 ranges, stored as `mentions` edge evidence): Heizung 46..<53, Marleen 119..<126, Lissabon 158..<166, Vermieter 219..<228, müde 262..<266. "Job" is not in the text, so `locate` drops it.

Summaries:

1. "Heute Morgen kaum geschlafen, weil die Heizung geklackert hat, und ich bin müde und genervt, weil ich den Vermieter nicht anrufe und mein Chef nach dem Release fragt, und ich keine Antwort habe."
2. "Heute Morgen kaum geschlafen, weil die Heizung geklackert hat, und ich bin müde und genervt, weil ich den Vermieter anrufen muss und im Büro keine Antwort auf den Release habe."
3. "Heute Morgen kaum geschlafen, weil die Heizung geklackert hat, und ich bin müde und genervt, weil ich den Vermieter nicht anrufe und im Büro keine Antwort auf den Release habe."

## Findings

- **Names and places are stable.** Marleen, Lissabon and Heizung came back every time.
- **Roles are missed or put under the wrong kind.** "Vermieter" was always a topic, though the prompt lists roles ("meine Mutter", "mein Chef") as people. "mein Chef" was never found. Büro and Wohnung were never found as places.
- **The word check does its job.** Run 2's invented "Job" never reaches the graph.
- **Feelings vary.** "müde" appeared in 2 of 3 runs.
- **The summary adds things the text does not say.** All three turn "eher müde als genervt" into "müde und genervt". Runs 1 and 3 add a reason ("weil ich den Vermieter nicht anrufe"). The prompt forbids both, but unlike concepts, the summary is not checked against the text. This goes against [ADR 0006](../decisions/0006-no-slop.md). Passed to the session building the understand step on 2026-10-20.

## Harness

`concepts.txt`, `summary.txt` and `thought.txt` were the two templates and the input above. Build with `swiftc -parse-as-library main.swift -o fmrun`, run with `./fmrun <dir>`.

```swift
import Foundation
import FoundationModels

@main struct Run {
  static func main() async throws {
    let dir = CommandLine.arguments[1]
    let text = try String(contentsOfFile: dir + "/thought.txt", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    let conceptsTpl = try String(contentsOfFile: dir + "/concepts.txt", encoding: .utf8)
    let summaryTpl = try String(contentsOfFile: dir + "/summary.txt", encoding: .utf8)
    print("availability:", SystemLanguageModel.default.availability)

    // Same shape as GenerationSchemaBuilder makes from prompts.json (properties sorted by name).
    let item = DynamicGenerationSchema(name: "Answer_concepts_item", properties: [
      .init(name: "kind", schema: DynamicGenerationSchema(name: "Answer_concepts_item_kind", anyOf: ["person","place","topic","emotion"])),
      .init(name: "mention", description: "die genauen Wörter aus dem Text", schema: DynamicGenerationSchema(type: String.self)),
      .init(name: "name", description: "Grundform, z. B. Marleen, Heizung, müde", schema: DynamicGenerationSchema(type: String.self)),
    ])
    let conceptsRoot = DynamicGenerationSchema(name: "Answer", properties: [
      .init(name: "concepts", schema: DynamicGenerationSchema(arrayOf: item, maximumElements: 20))])
    let summaryRoot = DynamicGenerationSchema(name: "Answer", properties: [
      .init(name: "summary", description: "ein Satz", schema: DynamicGenerationSchema(type: String.self))])

    let opts = GenerationOptions(temperature: 0.2)
    let c = try await LanguageModelSession(model: .default).respond(
      to: conceptsTpl.replacingOccurrences(of: "{{text}}", with: text),
      schema: try GenerationSchema(root: conceptsRoot, dependencies: []), options: opts)
    print("CONCEPTS:", c.content.jsonString)
    let s = try await LanguageModelSession(model: .default).respond(
      to: summaryTpl.replacingOccurrences(of: "{{text}}", with: text),
      schema: try GenerationSchema(root: summaryRoot, dependencies: []), options: opts)
    print("SUMMARY:", s.content.jsonString)
    print("WORDS:", text.split(whereSeparator: \.isWhitespace).count)
  }
}
```
