import Foundation
import Testing
import ElectricalSignoffCore
import ElectricalSignoffEvidence

@Suite("Electrical signoff observation contracts")
struct ElectricalSignoffObservationContractTests {
    @Test("maturity contains observation states only", .timeLimit(.minutes(1)))
    func maturityStates() {
        #expect(ElectricalSignoffObservationMaturity.corpusObserved.rawValue == "corpusObserved")
        #expect(ElectricalSignoffObservationMaturity.oracleCorrelated.rawValue == "oracleCorrelated")
    }

    @Test("metric expectation matches exact values", .timeLimit(.minutes(1)))
    func exactMetricExpectation() {
        let expectation = ElectricalSignoffMetricExpectation(name: "voltage", expectedValue: 1, unit: "V")
        #expect(expectation.matches(1))
        #expect(!expectation.matches(1.1))
    }

    @Test("metric expectation applies absolute tolerance", .timeLimit(.minutes(1)))
    func absoluteMetricTolerance() {
        let expectation = ElectricalSignoffMetricExpectation(
            name: "voltage",
            expectedValue: 1,
            unit: "V",
            absoluteTolerance: 0.1
        )
        #expect(expectation.matches(1.05))
    }

    @Test("metric expectation applies relative tolerance", .timeLimit(.minutes(1)))
    func relativeMetricTolerance() {
        let expectation = ElectricalSignoffMetricExpectation(
            name: "current",
            expectedValue: 10,
            unit: "A",
            relativeTolerance: 0.1
        )
        #expect(expectation.matches(10.5))
    }

    @Test("expected observations reject negative violations", .timeLimit(.minutes(1)))
    func negativeViolationCount() {
        let observation = ElectricalSignoffExpectedObservation(status: .completed, violationCount: -1)
        #expect(throws: ElectricalSignoffCorpusError.self) { try observation.validate() }
    }

    @Test("expected observations reject duplicate metric names", .timeLimit(.minutes(1)))
    func duplicateMetricNames() {
        let metric = ElectricalSignoffMetricExpectation(name: "voltage", expectedValue: 1, unit: "V")
        let observation = ElectricalSignoffExpectedObservation(
            status: .completed,
            violationCount: 0,
            metrics: [metric, metric]
        )
        #expect(throws: ElectricalSignoffCorpusError.self) { try observation.validate() }
    }

    @Test("corpus reports reject unsupported schemas", .timeLimit(.minutes(1)))
    func unsupportedReportSchema() {
        let report = ElectricalSignoffCorpusReport(
            corpusID: "corpus",
            corpusVersion: "1",
            pdkDigest: "pdk",
            implementationID: "engine",
            generatedAt: Date(timeIntervalSince1970: 1),
            completed: true,
            passed: true,
            observationMaturity: .corpusObserved,
            caseResults: [],
            schemaVersion: 99
        )
        #expect(throws: ElectricalSignoffCorpusError.self) { try report.validate() }
    }

    @Test("corpus reports do not encode flow authority", .timeLimit(.minutes(1)))
    func reportHasNoFlowAuthority() throws {
        let report = ElectricalSignoffCorpusReport(
            corpusID: "corpus",
            corpusVersion: "1",
            pdkDigest: "pdk",
            implementationID: "engine",
            generatedAt: Date(timeIntervalSince1970: 1),
            completed: true,
            passed: true,
            observationMaturity: .corpusObserved,
            caseResults: []
        )
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        #expect(object["approval"] == nil)
        #expect(object["releaseGate"] == nil)
        #expect(object["qualificationLevel"] == nil)
    }

    @Test("oracle observations require an artifact evidence binding", .timeLimit(.minutes(1)))
    func oracleArtifactBinding() throws {
        let observation = try makeTestOracleObservation(
            oracleID: "oracle",
            toolVersion: "1",
            pdkDigest: "pdk",
            status: .completed,
            violationCount: 0
        )
        #expect(observation.hasEvidenceBinding)
        try observation.validate()
    }
}
