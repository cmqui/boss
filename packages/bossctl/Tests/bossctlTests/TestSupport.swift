import Foundation

@testable import bossctl

final class RecordingOutputWriter: BossctlOutputWriting {
    private(set) var lines: [String] = []

    func writeLine(_ line: String) {
        lines.append(line)
    }
}
