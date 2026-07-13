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
    @Test("contract version starts at one")
    func contractVersion() {
        #expect(ElectricalSignoffEngineAPI.contractVersion == 1)
    }
}

