import Domain
import TestSupport
import Testing

@Suite("Embedder contract")
struct FakeEmbedderContractTests {
    @Test("the fake embedder keeps the contract every embedding engine must keep")
    func fakeKeepsContract() async throws {
        #expect(try await EmbedderContract.problems(of: FakeEmbedder(), dimensions: FakeEmbedder.dimensions) == [])
    }
}
