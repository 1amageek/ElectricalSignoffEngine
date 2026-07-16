// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let circuiteFoundationDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac")

let logicDesignDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "8e0c8c2c63152aa45bf12d943fa034bb1aba0f1e")

let pdkKitDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "aa145dfaa67454c44ac7767c37a28ab7f4b1d2e2")

let physicalDesignEngineDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PhysicalDesignEngine/Package.swift").path
)
    ? .package(path: "../PhysicalDesignEngine")
    : .package(url: "https://github.com/1amageek/PhysicalDesignEngine.git", revision: "2a3f4215319b8515120f19a5bcb5627122663ff3")

let pexEngineDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PEXEngine/Package.swift").path
)
    ? .package(path: "../PEXEngine")
    : .package(url: "https://github.com/1amageek/PEXEngine.git", revision: "2405356655e625c1bab6f20814f92af61c0caf2f")

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
