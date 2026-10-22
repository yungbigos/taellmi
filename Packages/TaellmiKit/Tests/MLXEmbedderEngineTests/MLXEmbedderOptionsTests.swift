import Domain
import MLXEmbedderEngine
import Testing

@Suite("MLX embedder options from config")
struct MLXEmbedderOptionsTests {
    private let template = "Instruct: Finde passende Stellen\nQuery:{{query}}"

    @Test("the size and the query phrasing come from the model's params")
    func readsParams() throws {
        let options = try MLXEmbedderOptions(params: [
            "dimensions": .number(512), "pooling": .string("last"), "query_template": .string(template),
        ])
        #expect(options.dimensions == 512)
        #expect(options.text("Zukunftsangst", for: .query) == "Instruct: Finde passende Stellen\nQuery:Zukunftsangst")
    }

    @Test("passages are embedded as they are, without the query phrasing")
    func documentsUnchanged() throws {
        let options = try MLXEmbedderOptions(params: [
            "dimensions": .number(512), "pooling": .string("last"), "query_template": .string(template),
        ])
        #expect(options.text("Heute war ich an der Isar.", for: .document) == "Heute war ich an der Isar.")
    }

    @Test("without a query template, the query is embedded as it is")
    func noTemplate() throws {
        let options = try MLXEmbedderOptions(params: ["dimensions": .number(256), "pooling": .string("mean")])
        #expect(options.text("Kim", for: .query) == "Kim")
    }

    @Test(
        "missing or invalid params are a clear error",
        arguments: [
            ([:], MLXEmbedderOptions.Error.missingParam("dimensions")),
            (["dimensions": .number(0), "pooling": .string("last")], .invalidDimensions(0)),
            (["dimensions": .number(512)], .missingParam("pooling")),
            (["dimensions": .number(512), "pooling": .string("max")], .unknownPooling("max")),
            (
                ["dimensions": .number(512), "pooling": .string("last"), "query_template": .string("no placeholder")],
                .templateWithoutQuery
            ),
        ] as [([String: JSONValue], MLXEmbedderOptions.Error)])
    func invalid(params: [String: JSONValue], error: MLXEmbedderOptions.Error) {
        #expect(throws: error) { try MLXEmbedderOptions(params: params) }
    }

    @Test("the seeded model's params are valid")
    func seededParams() throws {
        let options = try MLXEmbedderOptions(params: [
            "dimensions": .number(512), "pooling": .string("last"),
            "query_template": .string(
                "Instruct: Given a question or keywords, find passages of a personal journal that answer or match it\nQuery:{{query}}"
            ),
        ])
        #expect(options.dimensions == 512)
    }

    @Test("memory caps come from params, and are optional")
    func memoryCaps() throws {
        let capped = try MLXEmbedderOptions(params: [
            "dimensions": .number(512), "pooling": .string("last"), "cache_limit_mb": .number(256),
            "memory_limit_mb": .number(2048),
        ])
        #expect(capped.cacheLimitBytes == 256 * 1024 * 1024)
        #expect(capped.memoryLimitBytes == 2048 * 1024 * 1024)
        let uncapped = try MLXEmbedderOptions(params: ["dimensions": .number(512), "pooling": .string("last")])
        #expect(uncapped.cacheLimitBytes == nil)
        #expect(uncapped.memoryLimitBytes == nil)
    }
}
