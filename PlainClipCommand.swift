import Foundation

/// Compatibility parser for Plain Clip's one-shot command-line interface.
struct PlainClipCommand {
    let options: PlainTextCleaner.Options
    let pasteAfterCleaning: Bool

    private static let optionFlags: Set<String> = [
        "-w", "-l", "-m", "-i", "-r", "-b", "-s", "-p", "-a", "-q", "-n"
    ]
    private static let supportedFlags = optionFlags.union(["-v"])

    static func parse(_ arguments: [String]) -> PlainClipCommand? {
        let supplied = Array(arguments.dropFirst())
        let recognized = supplied.filter { $0 == "--plain-clip" || supportedFlags.contains($0) }
        guard supplied.contains("--plain-clip") || !recognized.isEmpty else { return nil }

        let flags = Set(recognized)
        let options = PlainTextCleaner.Options(
            trimTrailingLineWhitespace: flags.contains("-w"),
            trimLeadingLineWhitespace: flags.contains("-l"),
            trimWholeString: flags.contains("-m"),
            removeInvisibleCharacters: flags.contains("-i"),
            removeLineBreaks: flags.contains("-r"),
            removeBlankLines: flags.contains("-b"),
            collapseSpaces: flags.contains("-s"),
            replaceTabs: flags.contains("-p"),
            convertToASCII: flags.contains("-a"),
            straightenQuotes: flags.contains("-q"),
            normalizeUnicode: flags.contains("-n")
        )
        return PlainClipCommand(
            options: options,
            pasteAfterCleaning: flags.contains("-v")
        )
    }
}
