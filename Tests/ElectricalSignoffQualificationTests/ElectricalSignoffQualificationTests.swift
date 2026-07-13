import Foundation
import Testing
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import LogicIR
import PDKCore
import PhysicalDesignCore
import ToolQualification
import XcircuitePackage

@Suite("Electrical signoff qualification")
struct ElectricalSignoffQualificationTests {
    @Test("native corpus result is corpus-qualified but not oracle-qualified", .timeLimit(.minutes(1)))
    func nativeCorpusResult() async throws {
        let testCase = makeCase()
        let spec = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-fixture",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            cases: [testCase]
        )
        let report = try await ElectricalSignoffQualificationRunner(
            engine: StubElectricalSignoffEngine()
        ).run(spec: spec, generatedAt: Date(timeIntervalSince1970: 1_000))

        #expect(report.passed)
        #expect(report.qualificationLevel == .corpusChecked)
        #expect(report.caseCount == 1)
        #expect(report.matchedCaseCount == 1)
        #expect(report.caseResults.first?.cornerID == "typical")
        #expect(report.caseResults.first?.pdkCornerID == "typical")
        let evidence = report.toolEvidence(
            reportPath: "reports/electrical-corpus.json",
            reportSHA256: String(repeating: "a", count: 64),
            scope: makeScope(),
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )
        #expect(evidence.kind == .corpus)
        #expect(evidence.qualification?.qualified == true)
    }

    @Test("independent oracle agreement promotes the report to oracle-checked", .timeLimit(.minutes(1)))
    func independentOracleAgreement() async throws {
        let testCase = makeCase()
        let spec = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-fixture",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            requireIndependentOracle: true,
            cases: [testCase]
        )
        let report = try await ElectricalSignoffQualificationRunner(
            engine: StubElectricalSignoffEngine(),
            oracle: StubElectricalSignoffOracle()
        ).run(spec: spec)

        #expect(report.passed)
        #expect(report.qualificationLevel == .oracleChecked)
        #expect(report.oracleAgreementCount == 1)
    }

    @Test("required oracle disagreement cannot qualify the corpus", .timeLimit(.minutes(1)))
    func oracleDisagreementBlocksQualification() async throws {
        let testCase = makeCase()
        let spec = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-fixture",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            requireIndependentOracle: true,
            cases: [testCase]
        )
        let report = try await ElectricalSignoffQualificationRunner(
            engine: StubElectricalSignoffEngine(),
            oracle: DisagreeingElectricalSignoffOracle()
        ).run(spec: spec)

        #expect(!report.passed)
        #expect(report.qualificationLevel == .unknown)
        #expect(report.failureCodes.contains("oracle-disagreement"))
    }

    @Test("local oracle observation artifacts are independently validated and addressable", .timeLimit(.minutes(1)))
    func localOracleObservationArtifact() async throws {
        let testCase = makeCase()
        let observation = ElectricalSignoffOracleObservation(
            oracleID: "commercial-electrical-oracle",
            toolVersion: "fixture-1",
            pdkDigest: testCase.request.pdk.digest,
            status: .completed,
            violationCount: 0,
            metrics: [ElectricalSignoffPayload.Metric(name: "erc-violations", value: 0, unit: "count")]
        )
        let oracle = try LocalElectricalSignoffQualificationOracle(
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

    private func makeCase() -> ElectricalSignoffQualificationCase {
        let reference = XcircuiteFileReference(path: "fixture.json", kind: .other, format: .json)
        let request = ElectricalSignoffRequest(
            runID: "qualification-run",
            inputs: [reference],
            design: LogicDesignReference(artifact: reference, topDesignName: "top", designDigest: "design"),
            physicalDesign: PhysicalDesignReference(layoutArtifact: reference, topCell: "top", layoutDigest: "layout"),
            pdk: PDKReference(manifest: reference, processID: "fixture", version: "1", digest: "pdk-digest"),
            configuration: ElectricalSignoffConfiguration(requiredAxes: [.erc])
        )
        return ElectricalSignoffQualificationCase(
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

    private func makeScope() -> ToolQualificationScope {
        ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: String(repeating: "b", count: 64),
            algorithmVersion: "1",
            processProfileID: "fixture",
            deckDigest: "pdk-digest"
        )
    }
}

private struct StubElectricalSignoffEngine: ElectricalSignoffExecuting {
    func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> ElectricalSignoffRunResult {
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "stub",
            implementationID: "stub",
            implementationVersion: "1",
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
            return (axis, XcircuiteEngineResultEnvelope(
                schemaVersion: 1,
                runID: request.runID,
                status: .completed,
                metadata: metadata,
                payload: payload
            ))
        })
        return ElectricalSignoffRunResult(runID: request.runID, status: .completed, axisResults: results)
    }
}

private struct StubElectricalSignoffOracle: ElectricalSignoffQualificationOracle {
    func evaluate(_ testCase: ElectricalSignoffQualificationCase) async throws -> ElectricalSignoffOracleObservation {
        ElectricalSignoffOracleObservation(
            oracleID: "commercial-electrical-oracle",
            toolVersion: "fixture-1",
            pdkDigest: testCase.request.pdk.digest,
            status: .completed,
            violationCount: 0,
            metrics: [ElectricalSignoffPayload.Metric(name: "erc-violations", value: 0, unit: "count")]
        )
    }
}

private struct DisagreeingElectricalSignoffOracle: ElectricalSignoffQualificationOracle {
    func evaluate(_ testCase: ElectricalSignoffQualificationCase) async throws -> ElectricalSignoffOracleObservation {
        ElectricalSignoffOracleObservation(
            oracleID: "commercial-electrical-oracle",
            toolVersion: "fixture-1",
            pdkDigest: testCase.request.pdk.digest,
            status: .completed,
            violationCount: 1,
            metrics: [ElectricalSignoffPayload.Metric(name: "erc-violations", value: 1, unit: "count")]
        )
    }
}
