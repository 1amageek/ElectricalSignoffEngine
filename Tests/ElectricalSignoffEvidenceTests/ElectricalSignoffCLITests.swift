import Testing
import ElectricalSignoffCLICore

@Suite("Electrical signoff CLI")
struct ElectricalSignoffCLITests {
    @Test("flow authority options are not accepted by the engine CLI", .timeLimit(.minutes(1)))
    func flowAuthorityOptionIsRejected() async {
        let exitCode = await ElectricalSignoffCommand().run(arguments: [
            "--release-gate-request", "gate-request.json",
        ])

        #expect(exitCode == 1)
    }
}
