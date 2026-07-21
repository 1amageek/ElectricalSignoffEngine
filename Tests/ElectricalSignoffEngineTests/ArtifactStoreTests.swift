import Foundation
import Testing
import CircuiteFoundation
@testable import ElectricalSignoffCore

@Suite("Electrical artifact stores")
struct ArtifactStoreTests {
    @Test("path segments reject traversal and separators")
    func pathSegmentsRejectUnsafeValues() throws {
        #expect(throws: ElectricalArtifactStoreError.invalidPathSegment("..")) {
            _ = try ElectricalArtifactPathSegment(validating: "..")
        }
        #expect(throws: ElectricalArtifactStoreError.invalidPathSegment("run/escape")) {
            _ = try ElectricalArtifactPathSegment(validating: "run/escape")
        }
        #expect(throws: ElectricalArtifactStoreError.invalidPathSegment("run\\escape")) {
            _ = try ElectricalArtifactPathSegment(validating: "run\\escape")
        }
        #expect(try ElectricalArtifactNamespace(validating: ".xcircuite/runs").relativePath == ".xcircuite/runs")
        #expect(throws: ElectricalArtifactStoreError.invalidNamespace("/runs")) {
            _ = try ElectricalArtifactNamespace(validating: "/runs")
        }
    }

    @Test("in-memory storage is immutable")
    func inMemoryStorageRejectsDuplicatesAndConflicts() async throws {
        let store = InMemoryElectricalArtifactStore()
        let data = Data("first".utf8)
        let producer = try producer()
        let reference = try await store.store(
            data: data,
            artifactID: "report",
            runID: "run-1",
            axis: .erc,
            producer: producer
        )
        #expect(reference.path == "electrical-signoff/run-1/erc/report.json")

        await #expect(throws: ElectricalArtifactStoreError.duplicateArtifact(reference.path)) {
            _ = try await store.store(
                data: data,
                artifactID: "report",
                runID: "run-1",
                axis: .erc,
                producer: producer
            )
        }
        await #expect(throws: ElectricalArtifactStoreError.conflictingArtifact(reference.path)) {
            _ = try await store.store(
                data: Data("second".utf8),
                artifactID: "report",
                runID: "run-1",
                axis: .erc,
                producer: producer
            )
        }
    }

    @Test("local storage is contained and immutable")
    func localStorageRejectsDuplicatesAndConflicts() async throws {
        let root = try temporaryDirectory(named: "immutable")
        defer { removeTemporaryDirectory(root) }
        let store = try LocalElectricalArtifactStore(
            artifactRoot: root,
            namespace: .electricalSignoff
        )
        let data = Data("first".utf8)
        let producer = try producer()
        let reference = try await store.store(
            data: data,
            artifactID: "report",
            runID: "run-1",
            axis: .erc,
            producer: producer
        )
        #expect(reference.path == "electrical-signoff/run-1/erc/report.json")
        #expect(try Data(contentsOf: root.appending(path: reference.path)) == data)

        await #expect(throws: ElectricalArtifactStoreError.duplicateArtifact(reference.path)) {
            _ = try await store.store(
                data: data,
                artifactID: "report",
                runID: "run-1",
                axis: .erc,
                producer: producer
            )
        }
        await #expect(throws: ElectricalArtifactStoreError.conflictingArtifact(reference.path)) {
            _ = try await store.store(
                data: Data("second".utf8),
                artifactID: "report",
                runID: "run-1",
                axis: .erc,
                producer: producer
            )
        }
    }

    @Test("local storage rejects symbolic-link escapes")
    func localStorageRejectsSymbolicLinkEscape() async throws {
        let root = try temporaryDirectory(named: "symlink-root")
        let outside = try temporaryDirectory(named: "symlink-outside")
        defer {
            removeTemporaryDirectory(root)
            removeTemporaryDirectory(outside)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "electrical-signoff"),
            withDestinationURL: outside
        )
        let store = try LocalElectricalArtifactStore(
            artifactRoot: root,
            namespace: .electricalSignoff
        )
        let producer = try producer()

        await #expect(throws: ElectricalArtifactStoreError.symbolicLinkInPath(
            root.appending(path: "electrical-signoff").path(percentEncoded: false)
        )) {
            _ = try await store.store(
                data: Data("data".utf8),
                artifactID: "report",
                runID: "run-1",
                axis: .erc,
                producer: producer
            )
        }
    }

    @Test("local storage revalidates a root created after initialization")
    func localStorageRejectsRootReplacedBySymbolicLink() async throws {
        let parent = try temporaryDirectory(named: "late-symlink-parent")
        let outside = try temporaryDirectory(named: "late-symlink-outside")
        defer {
            removeTemporaryDirectory(parent)
            removeTemporaryDirectory(outside)
        }
        let root = parent.appending(path: "artifacts")
        let store = try LocalElectricalArtifactStore(
            artifactRoot: root,
            namespace: .electricalSignoff
        )
        let producer = try producer()
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)

        await #expect(throws: ElectricalArtifactStoreError.rootIsSymbolicLink(
            root.path(percentEncoded: false)
        )) {
            _ = try await store.store(
                data: Data("data".utf8),
                artifactID: "report",
                runID: "run-1",
                axis: .erc,
                producer: producer
            )
        }
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "electrical-artifact-store-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func producer() throws -> ProducerIdentity {
        try ProducerIdentity(
            kind: .engine,
            identifier: "electrical-signoff.erc",
            version: "1.0.0",
            build: String(repeating: "a", count: 64)
        )
    }

    private func removeTemporaryDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove temporary electrical artifact directory: \(error)")
        }
    }
}
