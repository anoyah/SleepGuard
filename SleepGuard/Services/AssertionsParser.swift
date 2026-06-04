import Foundation

struct AssertionsParser {
    func parse(_ output: String, capturedAt: Date = Date()) -> ParsedAssertions {
        var status = AssertionStatus()
        var processAssertions: [ProcessAssertion] = []
        var kernelAssertions: [KernelAssertion] = []
        var section: Section = .none

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("Assertion status system-wide:") {
                section = .systemWide
                continue
            }
            if line.hasPrefix("Listed by owning process:") {
                section = .owningProcess
                continue
            }
            if line.hasPrefix("Kernel Assertions:") {
                section = .kernel
                status.hasKernelAssertions = !line.contains("None") && !line.hasSuffix("0")
                continue
            }

            switch section {
            case .systemWide:
                parseSystemStatusLine(line, into: &status)
            case .owningProcess:
                if line.hasPrefix("pid "), let assertion = parseProcessLine(line) {
                    processAssertions.append(assertion)
                } else if line.hasPrefix("Timeout will fire"), !processAssertions.isEmpty {
                    processAssertions[processAssertions.count - 1].timeout = line
                }
            case .kernel:
                if line.hasPrefix("id="), let assertion = parseKernelLine(line) {
                    kernelAssertions.append(assertion)
                    status.hasKernelAssertions = true
                }
            case .none:
                continue
            }
        }

        return ParsedAssertions(
            capturedAt: capturedAt,
            systemStatus: status,
            processAssertions: processAssertions,
            kernelAssertions: kernelAssertions,
            rawOutput: output
        )
    }

    private func parseSystemStatusLine(_ line: String, into status: inout AssertionStatus) {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 2, let value = Int(parts[1]) else { return }
        status.set(name: parts[0], active: value != 0)
    }

    private func parseProcessLine(_ line: String) -> ProcessAssertion? {
        let pattern = #"^pid\s+(\d+)\(([^)]+)\):\s+\[[^\]]+\]\s+([0-9:]+)\s+(\S+)\s+named:\s+"([^"]*)""#
        guard let match = firstMatch(pattern: pattern, in: line), match.count >= 6 else {
            return nil
        }
        let duration = match[3]
        return ProcessAssertion(
            pid: Int(match[1]) ?? 0,
            processName: match[2],
            duration: duration,
            durationSeconds: Self.durationSeconds(duration),
            assertionType: match[4],
            reason: match[5],
            timeout: nil,
            rawLine: line
        )
    }

    private func parseKernelLine(_ line: String) -> KernelAssertion? {
        let code = firstMatch(pattern: #"(0x[0-9a-fA-F]+=\S+)"#, in: line)?.dropFirst().first ?? "Kernel"
        let description = firstMatch(pattern: #"description=([^\s]+)"#, in: line)?.dropFirst().first ?? ""
        let owner = firstMatch(pattern: #"owner=(.+)$"#, in: line)?.dropFirst().first ?? L("未知 USB 设备", "Unknown USB Device")
        return KernelAssertion(assertionCode: code, owner: owner, description: description, rawLine: line)
    }

    private func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    static func durationSeconds(_ duration: String) -> Int? {
        let parts = duration.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private enum Section {
        case none
        case systemWide
        case owningProcess
        case kernel
    }
}
