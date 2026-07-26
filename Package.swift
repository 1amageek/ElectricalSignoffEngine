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
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "dc792c88e189c822c9f83ea86cf139ee68560dca")

let logicDesignDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "e8f8e1dace0445ddd816929c4ca0fe17cca12a7b")

let pdkKitDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "3ab7e3b6094d2de672b582d90076cf58b6527766")

let physicalDesignEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PhysicalDesignEngine/Package.swift").path
)
    ? .package(path: "../PhysicalDesignEngine")
    : .package(url: "https://github.com/1amageek/PhysicalDesignEngine.git", revision: "a7bf05dc88da9daea37e256c32d73418484d2a28")

let pexEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PEXEngine/Package.swift").path
)
    ? .package(path: "../PEXEngine")
    : .package(url: "https://github.com/1amageek/PEXEngine.git", revision: "c2dc912203790d862a2055bd6abd9a0a1dc86b6b")

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
        .library(name: "ElectricalSignoffCLICore", targets: ["ElectricalSignoffCLICore"]),
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
        .target(
            name: "ElectricalSignoffCLICore",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                "ElectricalSignoffCore",
                "ElectricalSignoffEngine",
                "ElectricalSignoffEvidence",
            ]
        ),
        .executableTarget(
            name: "ElectricalSignoffCLI",
            dependencies: ["ElectricalSignoffCLICore"]
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
                "ElectricalSignoffCLICore",
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
    ]
)
