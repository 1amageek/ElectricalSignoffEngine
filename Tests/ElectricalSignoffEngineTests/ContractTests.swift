import Testing
@testable import ElectricalSignoffCore
@testable import PowerIntegrityEngine
@testable import ERCEngine
@testable import ESDEngine
@testable import LatchUpEngine
@testable import AgingEngine
@testable import ElectricalSignoffEngine

@Suite("ElectricalSignoffEngine contract")
struct ContractTests {
    @Test("run result schema version starts at one")
    func runResultSchemaVersion() {
        #expect(ElectricalSignoffRunResult.currentSchemaVersion == 1)
    }

    @Test("capability snapshot reflects the concrete engine")
    func capabilitySnapshot() {
        let snapshot = ElectricalSignoffEngine.capability

        #expect(snapshot.engineID == "ElectricalSignoffEngine")
        #expect(snapshot.supportedAxes == ElectricalSignoffEngine.supportedAxes)
    }
}
