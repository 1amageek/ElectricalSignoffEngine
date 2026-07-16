import Foundation
import Testing
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffEvidence
import LogicIR
import PDKCore
import PhysicalDesignCore
import CircuiteFoundation

@Suite("Electrical signoff corpus observations")
struct ElectricalSignoffEvidenceTests {
    @Test("native corpus result records corpus observations", .timeLimit(.minutes(1)))
    func nativeCorpusResult() async throws {
        let testCase = try makeCase()
        let spec = ElectricalSignoffCorpusSpec(
            corpusID: "electrical-fixture",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            cases: [testCase]
        )
        let report = try await ElectricalSignoffCorpusRunner(
            engine: StubElectricalSignoffEngine()
        ).run(spec: spec, generatedAt: Date(timeIntervalSince1970: 1_000))

        #expect(report.passed)
        #expect(report.observationMaturity == .corpusObserved)
        #expect(report.caseCount == 1)
        #expect(report.matchedCaseCount == 1)
        #expect(report.caseResults.first?.cornerID == "typical")
        #expect(report.caseResults.first?.pdkCornerID == "typical")
    }

    @Test("external oracle agreement records correlated observations", .timeLimit(.minutes(1)))
    func independentOracleAgreement() async throws {
        let testCase = try makeCase()
        let spec = ElectricalSignoffCorpusSpec(
            corpusID: "electrical-fixture",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            requireExternalOracleEvidence: true,
            cases: [testCase]
        )
        let report = try await ElectricalSignoffCorpusRunner(
            engine: StubElectricalSignoffEngine(),
            oracle: StubElectricalSignoffOracle()
        ).run(spec: spec)

        #expect(report.passed)
        #expect(report.observationMaturity == .oracleCorrelated)
        #expect(report.oracleAgreementCount == 1)
    }

    @Test("required oracle disagreement fails corpus observation matching", .timeLimit(.minutes(1)))
    func oracleDisagreementFailsCorpus() async throws {
        let testCase = try makeCase()
        let spec = ElectricalSignoffCorpusSpec(
            corpusID: "electrical-fixture",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            requireExternalOracleEvidence: true,
            cases: [testCase]
        )
        let report = try await ElectricalSignoffCorpusRunner(
            engine: StubElectricalSignoffEngine(),
            oracle: DisagreeingElectricalSignoffOracle()
        ).run(spec: spec)

        #expect(!report.passed)
        #expect(report.observationMaturity == .oracleCorrelated)
        #expect(report.failureCodes.contains("oracle-disagreement"))
    }

    @Test("local oracle observation artifacts are integrity-bound and addressable", .timeLimit(.minutes(1)))
    func localOracleObservationArtifact() async throws {
        let testCase = try makeCase()
        let observation = try makeTestOracleObservation(
            oracleID: "commercial-electrical-oracle",
            toolVersion: "fixture-1",
            pdkDigest: testCase.request.pdk.digest,
            status: .completed,
            violationCount: 0,
            metrics: [ElectricalSignoffPayload.Metric(name: "erc-violations", value: 0, unit: "count")]
        )
        let oracle = try LocalElectricalSignoffOracle(
            observationSet: ElectricalSignoffOracleObservationSet(
                oracleID: observation.oracleID,
                toolVersion: observation.toolVersion,
                pdkDigest: observation.pdkDigest,
                observations: [ElectricalSignoffOracleObservationSet.Entry(
                    caseID: testCase.caseID,
                    observation: observation
                )]
            )
        )

        let loaded = try await oracle.evaluate(testCase)
        #expect(loaded == observation)
    }

    private func makeCase() throws -> ElectricalSignoffCorpusCase {
        let reference = try ArtifactReference(
            id: ArtifactID(rawValue: "fixture"),
            locator: ArtifactLocator(
                location: ArtifactLocation(workspaceRelativePath: "fixture.json"),
                role: .input,
                kind: .other,
                format: .json
            ),
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "a", count: 64)
            ),
            byteCount: 1
        )
        let request = ElectricalSignoffRequest(
            runID: "qualification-run",
            inputs: [reference],
            design: LogicDesignReference(artifact: reference, topDesignName: "top", designDigest: "design"),
            physicalDesign: PhysicalDesignReference(layoutArtifact: reference, topCell: "top", layoutDigest: "layout"),
            pdk: PDKReference(manifest: reference, processID: "fixture", version: "1", digest: "pdk-digest"),
            configuration: ElectricalSignoffConfiguration(requiredAxes: [.erc])
        )
        return ElectricalSignoffCorpusCase(
            caseID: "clean-erc",
            kind: .positive,
            axis: .erc,
            request: request,
            expected: ElectricalSignoffExpectedObservation(
                status: .completed,
                violationCount: 0,
                metrics: [ElectricalSignoffMetricExpectation(name: "erc-violations", expectedValue: 0, unit: "count")]
            )
        )
    }

}

private struct StubElectricalSignoffEngine: ElectricalSignoffExecuting {
    func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> ElectricalSignoffRunResult {
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "stub",
                version: "1"
            ),
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 1)
        )
        let results = Dictionary(uniqueKeysWithValues: axes.map { axis in
            let payload = ElectricalSignoffPayload(
                violationCount: 0,
                axis: axis,
                metrics: [ElectricalSignoffPayload.Metric(name: "erc-violations", value: 0, unit: "count")],
                cornerID: request.configuration.operatingCondition.id
            )
            return (axis, ElectricalSignoffResult(
                schemaVersion: 1,
                runID: request.runID,
                status: .completed,
                provenance: provenance,
                payload: payload
            ))
        })
        return ElectricalSignoffRunResult(
            runID: request.runID,
            status: .completed,
            axisResults: results,
            provenance: provenance
        )
    }
}

private struct StubElectricalSignoffOracle: ElectricalSignoffOracle {
    func evaluate(_ testCase: ElectricalSignoffCorpusCase) async throws -> ElectricalSignoffOracleObservation {
        try makeTestOracleObservation(
            oracleID: "commercial-electrical-oracle",
            toolVersion: "fixture-1",
            pdkDigest: testCase.request.pdk.digest,
            status: .completed,
            violationCount: 0,
            metrics: [ElectricalSignoffPayload.Metric(name: "erc-violations", value: 0, unit: "count")]
        )
    }
}

private struct DisagreeingElectricalSignoffOracle: ElectricalSignoffOracle {
    func evaluate(_ testCase: ElectricalSignoffCorpusCase) async throws -> ElectricalSignoffOracleObservation {
        try makeTestOracleObservation(
            oracleID: "commercial-electrical-oracle",
            toolVersion: "fixture-1",
            pdkDigest: testCase.request.pdk.digest,
            status: .completed,
            violationCount: 1,
            metrics: [ElectricalSignoffPayload.Metric(name: "erc-violations", value: 1, unit: "count")]
        )
    }
}
