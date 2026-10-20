import Features
import Testing

@Suite("Saving and using the Recovery Key")
struct RecoveryKeyViewModelTests {
    @Test("the wrong last group is refused with a calm message; the right one finishes")
    func confirm() async {
        var kept: Bool?
        let model = RecoveryKeyViewModel(recoveryKey: "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE-FFFFF") { group, keep in
            kept = keep
            return group == "FFFFF"
        }
        model.typedGroup = "ZZZZZ"
        await model.confirm()
        #expect(!model.isDone)
        #expect(model.message == "that doesn't match the last group. check and try again.")
        model.typedGroup = "FFFFF"
        model.keepInKeychain = true
        await model.confirm()
        #expect(model.isDone)
        #expect(kept == true)
    }

    @Test("unlocking with a key that doesn't fit says so")
    func unlock() async {
        let model = UnlockArchiveViewModel { text in text == "right" }
        model.typed = "wrong"
        await model.unlock()
        #expect(!model.isUnlocked)
        #expect(model.message == "that recovery key doesn't fit this archive. check it and try again.")
        model.typed = "right"
        await model.unlock()
        #expect(model.isUnlocked)
    }
}
