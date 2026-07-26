import Foundation
import ElectricalSignoffCLICore

@main
public struct ElectricalSignoffCLI {
    public static func main() async {
        let code = await ElectricalSignoffCommand().run(
            arguments: Array(CommandLine.arguments.dropFirst())
        )
        Foundation.exit(Int32(code))
    }
}
