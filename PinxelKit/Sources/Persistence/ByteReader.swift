import Foundation

/// Little-endian reads with bounds checking; offsets relative to the start of the data.
struct ByteReader {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var count: Int { data.count }

    private func check(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset <= data.count - length else {
            throw ZipError.corrupt("read out of bounds at \(offset)")
        }
    }

    func uint16(at offset: Int) throws -> UInt16 {
        try check(offset, 2)
        let i = data.startIndex + offset
        return UInt16(data[i]) | UInt16(data[i + 1]) << 8
    }

    func uint32(at offset: Int) throws -> UInt32 {
        try check(offset, 4)
        let i = data.startIndex + offset
        return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 3]) << 24
    }

    func bytes(at offset: Int, count length: Int) throws -> Data {
        try check(offset, length)
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + length))
    }
}
