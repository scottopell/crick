public enum CommandLineError: Error, Equatable, Sendable {
    case missingCommand
    case unknownCommand(String)
    case invalidArguments
    case unknownOption(String)
    case duplicateOption(String)
    case missingOptionValue(String)
    case unknownScenario(String)
    case invalidTickCount(String)
}

public struct RunRequest: Equatable, Sendable {
    public var scenario: ScenarioDefinition
    public var jsonPath: String?
    public var csvPath: String?
    public var snapshotPath: String?
}

public struct ResumeRequest: Equatable, Sendable {
    public var snapshotPath: String
    public var tickCount: UInt64
    public var outputSnapshotPath: String?
}

public enum CommandLineRequest: Equatable, Sendable {
    case list
    case run(RunRequest)
    case resume(ResumeRequest)

    public static func parse(_ arguments: [String]) throws -> Self {
        guard let command = arguments.first else {
            throw CommandLineError.missingCommand
        }
        switch command {
        case "list":
            guard arguments.count == 1 else {
                throw CommandLineError.invalidArguments
            }
            return .list
        case "run":
            guard arguments.count >= 2 else {
                throw CommandLineError.invalidArguments
            }
            guard let scenario = BuiltInScenarios.named(arguments[1]) else {
                throw CommandLineError.unknownScenario(arguments[1])
            }
            let options = try parseOptions(
                Array(arguments.dropFirst(2)),
                allowed: ["--json", "--csv", "--snapshot"]
            )
            return .run(RunRequest(
                scenario: scenario,
                jsonPath: options["--json"],
                csvPath: options["--csv"],
                snapshotPath: options["--snapshot"]
            ))
        case "resume":
            guard arguments.count >= 2 else {
                throw CommandLineError.invalidArguments
            }
            let options = try parseOptions(
                Array(arguments.dropFirst(2)),
                allowed: ["--ticks", "--snapshot"]
            )
            guard let tickText = options["--ticks"] else {
                throw CommandLineError.invalidArguments
            }
            guard let ticks = UInt64(tickText) else {
                throw CommandLineError.invalidTickCount(tickText)
            }
            return .resume(ResumeRequest(
                snapshotPath: arguments[1],
                tickCount: ticks,
                outputSnapshotPath: options["--snapshot"]
            ))
        default:
            throw CommandLineError.unknownCommand(command)
        }
    }

    private static func parseOptions(
        _ arguments: [String],
        allowed: Set<String>
    ) throws -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard option.hasPrefix("--"), allowed.contains(option) else {
                throw CommandLineError.unknownOption(option)
            }
            guard options[option] == nil else {
                throw CommandLineError.duplicateOption(option)
            }
            guard index + 1 < arguments.count,
                  !arguments[index + 1].hasPrefix("--") else {
                throw CommandLineError.missingOptionValue(option)
            }
            options[option] = arguments[index + 1]
            index += 2
        }
        return options
    }
}
