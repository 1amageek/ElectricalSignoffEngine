// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "7abcac83517935c9b9f7553d7016d62cffde259d")

let logicDesignDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "b9aa25b0b78e6168befa25df3bfe8309bd020a6d")

let pdkKitDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "b62c5ad7e5819a24977038c2133856caed52f481")

let physicalDesignEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PhysicalDesignEngine/Package.swift").path
)
    ? .package(path: "../PhysicalDesignEngine")
    : .package(url: "https://github.com/1amageek/PhysicalDesignEngine.git", revision: "a2b64a3f9f1651be0601496a7423a211c1438c49")

let pexEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PEXEngine/Package.swift").path
)
    ? .package(path: "../PEXEngine")
    : .package(url: "https://github.com/1amageek/PEXEngine.git", revision: "ba10c1fe0b847d5816faef4eae67c64a19d61e1e")

let package = Package(
    name: "ElectricalSignoffEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ElectricalSignoffCore", targets: ["ElectricalSignoffCore"]),
        .library(name: "PowerIntegrityEngine", targets: ["PowerIntegrityEngine"]),
        .library(name: "ERCEngine", targets: ["ERCEngine"]),
        .library(name: "ESDEngine", targets: ["ESDEngine"]),
        .library(name: "LatchUpEngine", targets: ["LatchUpEngine"]),
        .library(name: "AgingEngine", targets: ["AgingEngine"]),
        .library(name: "ElectricalSignoffEngine", targets: ["ElectricalSignoffEngine"]),
        .library(name: "ElectricalSignoffEvidence", targets: ["ElectricalSignoffEvidence"]),
        .executable(name: "electrical-signoff", targets: ["ElectricalSignoffCLI"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
        logicDesignDependency,
        pdkKitDependency,
        physicalDesignEngineDependency,
        pexEngineDependency,
    ],
    targets: [
        .target(
            name: "ElectricalSignoffCore",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "PowerIntent", package: "LogicDesign"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "PEXCore", package: "PEXEngine"),
                .product(name: "PEXParsers", package: "PEXEngine"),
            ]
        ),
        .target(
            name: "PowerIntegrityEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "ElectricalSignoffCore"]
        ),
        .target(
            name: "ERCEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "ElectricalSignoffCore"]
        ),
        .target(
            name: "ESDEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "ElectricalSignoffCore"]
        ),
        .target(
            name: "LatchUpEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "ElectricalSignoffCore"]
        ),
        .target(
            name: "AgingEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "ElectricalSignoffCore"]
        ),
        .target(
            name: "ElectricalSignoffEngine",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                "ElectricalSignoffCore",
                "PowerIntegrityEngine",
                "ERCEngine",
                "ESDEngine",
                "LatchUpEngine",
                "AgingEngine",
            ]
        ),
        .target(
            name: "ElectricalSignoffEvidence",
            dependencies: [
                "ElectricalSignoffCore",
                "ElectricalSignoffEngine",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .executableTarget(
            name: "ElectricalSignoffCLI",
            dependencies: ["ElectricalSignoffCore", "ElectricalSignoffEngine", "ElectricalSignoffEvidence"]
        ),
        .testTarget(
            name: "ElectricalSignoffEngineTests",
            dependencies: [
                "ElectricalSignoffCore",
                "PowerIntegrityEngine",
                "ERCEngine",
                "ESDEngine",
                "LatchUpEngine",
                "AgingEngine",
                "ElectricalSignoffEngine",
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "PEXCore", package: "PEXEngine"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "ElectricalSignoffEvidenceTests",
            dependencies: [
                "ElectricalSignoffCore",
                "ElectricalSignoffEngine",
                "ElectricalSignoffEvidence",
                "ElectricalSignoffCLI",
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
    ]
)
