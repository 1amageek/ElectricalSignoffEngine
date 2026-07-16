import Foundation
import Testing
import ElectricalSignoffCore
import ElectricalSignoffEvidence

@Suite("Electrical signoff evidence boundary")
struct ElectricalSignoffEvidenceBoundaryTests {
    @Test("observation maturity is a raw corpus property", .timeLimit(.minutes(1)))
    func observationMaturityRoundTrip() throws {
        let data = try JSONEncoder().encode(ElectricalSignoffObservationMaturity.oracleCorrelated)
        #expect(try JSONDecoder().decode(ElectricalSignoffObservationMaturity.self, from: data) == .oracleCorrelated)
    }

    @Test("corpus errors describe observation failures without trust decisions", .timeLimit(.minutes(1)))
    func corpusErrorDescription() {
        let error = ElectricalSignoffCorpusError.missingAxisResult("erc")
        #expect(error.localizedDescription.contains("corpus result"))
    }

    @Test("oracle observation sets reject duplicate case identities", .timeLimit(.minutes(1)))
    func duplicateOracleCaseIdentity() throws {
        let observation = try makeTestOracleObservation(
            oracleID: "oracle",
            toolVersion: "1",
            pdkDigest: "pdk",
            status: .completed,
            violationCount: 0
        )
        let set = ElectricalSignoffOracleObservationSet(
            oracleID: observation.oracleID,
            toolVersion: observation.toolVersion,
            pdkDigest: observation.pdkDigest,
            observations: [
                .init(caseID: "case", observation: observation),
                .init(caseID: "case", observation: observation),
            ]
        )

        #expect(throws: ElectricalSignoffCorpusError.self) {
            try set.validate()
        }
    }
}
