import Foundation

public struct BleSegmentReassembler: Sendable {
    private var segments: [Int: Data] = [:]
    private var expectedMaxIndex: Int?
    private var chunkSize: Int?

    public init() {}

    public mutating func push(_ segment: Data) throws -> Data? {
        guard let header = segment.first else {
            throw BleReassemblyError.emptySegment
        }
        guard segment.count >= 2 else {
            throw BleReassemblyError.segmentTooShort(segment.count)
        }

        if header == 0x00 {
            reset()
            return Data(segment.dropFirst())
        }

        let maxIndex = Int((header >> 4) & 0x0F)
        let segmentIndex = Int(header & 0x0F)

        guard segmentIndex <= maxIndex else {
            throw BleReassemblyError.invalidSegmentIndex(segmentIndex)
        }

        if let expectedMaxIndex, expectedMaxIndex != maxIndex {
            throw BleReassemblyError.inconsistentSegmentSeries(expectedMaxIndex: expectedMaxIndex, actualMaxIndex: maxIndex)
        }
        if segments[segmentIndex] != nil {
            throw BleReassemblyError.duplicateSegmentIndex(segmentIndex)
        }

        expectedMaxIndex = maxIndex
        chunkSize = chunkSize ?? (segment.count - 1)
        segments[segmentIndex] = Data(segment.dropFirst())

        let isLastSegment = maxIndex == segmentIndex
        guard isLastSegment else {
            return nil
        }

        let expectedCount = maxIndex + 1
        guard segments.count == expectedCount else {
            throw BleReassemblyError.missingSegments(expected: expectedCount, actual: segments.count)
        }

        guard let chunkSize else {
            throw BleReassemblyError.missingSegments(expected: expectedCount, actual: 0)
        }

        var output = Data()
        output.reserveCapacity(segments.values.reduce(0) { $0 + $1.count })
        for index in 0..<expectedCount {
            guard let chunk = segments[index] else {
                throw BleReassemblyError.missingSegments(expected: expectedCount, actual: segments.count)
            }
            if index < maxIndex && chunk.count != chunkSize {
                throw BleReassemblyError.segmentTooShort(chunk.count + 1)
            }
            output.append(chunk)
        }
        reset()
        return output
    }

    private mutating func reset() {
        segments = [:]
        expectedMaxIndex = nil
        chunkSize = nil
    }
}
