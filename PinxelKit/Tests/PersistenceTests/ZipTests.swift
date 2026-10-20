import Foundation
import Testing
@testable import Persistence

struct ZipTests {
    func archive(_ entries: [(String, Data, ZipWriter.Method)]) throws -> Data {
        var writer = ZipWriter()
        for (name, data, method) in entries { try writer.add(name: name, data: data, method: method) }
        return try writer.finish()
    }

    /// Offset of the first central directory entry (signature PK\u{1}\u{2}).
    func centralDirectoryOffset(in data: Data) -> Int {
        let bytes = [UInt8](data)
        for i in 0..<(bytes.count - 4) where bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02 {
            return i
        }
        return -1
    }

    @Test func crc32KnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF43926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test func roundTripStoreAndDeflate() throws {
        let text = Data(String(repeating: "pinxel ", count: 2000).utf8)
        let binary = Data((0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let zip = try archive([("doc.json", text, .deflate), ("image.png", binary, .store), ("empty.txt", Data(), .deflate), ("àèì/ü.txt", Data("ok".utf8), .store)])
        #expect(zip.count < text.count) // the repetitive JSON was compressed
        let reader = try ZipReader(zip)
        #expect(reader.entries.map(\.name) == ["doc.json", "image.png", "empty.txt", "àèì/ü.txt"])
        #expect(try reader.data(for: "doc.json") == text)
        #expect(try reader.data(for: "image.png") == binary)
        #expect(try reader.data(for: "empty.txt") == Data())
        #expect(try reader.data(for: "àèì/ü.txt") == Data("ok".utf8))
    }

    @Test func zipIsReadableBySystemUnzip() throws {
        let zip = try archive([("hello.txt", Data(String(repeating: "ciao ", count: 100).utf8), .deflate)])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-\(UUID().uuidString).zip")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-tq", url.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func missingEntry() throws {
        let reader = try ZipReader(archive([("a.txt", Data("a".utf8), .store)]))
        #expect(throws: ZipError.missingEntry("b.txt")) { try reader.data(for: "b.txt") }
    }

    @Test func rejectsPathTraversal() throws {
        for name in ["../evil.txt", "/etc/passwd", "a\\b.txt", "assets/../../x", "a//b", "./x"] {
            let zip = try archive([(name, Data("x".utf8), .store)])
            #expect(throws: ZipError.unsafeEntryName(name)) { try ZipReader(zip) }
        }
    }

    @Test func rejectsTooManyEntries() throws {
        let zip = try archive((0..<4).map { ("f\($0).txt", Data("x".utf8), ZipWriter.Method.store) })
        #expect(throws: ZipError.tooManyEntries(4)) { try ZipReader(zip, limits: ZipLimits(maxEntries: 3)) }
    }

    @Test func rejectsTotalSizeOverLimit() throws {
        let zip = try archive([("big.bin", Data(count: 5000), .deflate)])
        #expect(throws: ZipError.entryTooLarge("big.bin")) {
            try ZipReader(zip, limits: ZipLimits(maxTotalUncompressedSize: 1000))
        }
    }

    @Test func rejectsTruncatedAndGarbage() throws {
        let zip = try archive([("a.txt", Data("hello".utf8), .store)])
        #expect(throws: ZipError.self) { try ZipReader(zip.prefix(zip.count - 10)) }
        #expect(throws: ZipError.self) { try ZipReader(Data((0..<500).map { UInt8(truncatingIfNeeded: $0 * 7) })) }
        #expect(throws: ZipError.self) { try ZipReader(Data()) }
    }

    @Test func detectsChecksumMismatch() throws {
        var zip = try archive([("a.txt", Data("hello world".utf8), .store)])
        // The stored content starts after the local header (30 bytes) and the name (5 bytes).
        zip[zip.startIndex + 35] ^= 0xFF
        let reader = try ZipReader(zip)
        #expect(throws: ZipError.checksumMismatch("a.txt")) { try reader.data(for: "a.txt") }
    }

    @Test func zipBombWithLyingSizeIsStopped() throws {
        var zip = try archive([("bomb.bin", Data(count: 1_000_000), .deflate)])
        // The central directory declares 10 decompressed bytes instead of 1 MB.
        let cd = centralDirectoryOffset(in: zip)
        #expect(cd > 0)
        for (i, byte) in [UInt8(10), 0, 0, 0].enumerated() { zip[zip.startIndex + cd + 24 + i] = byte }
        let reader = try ZipReader(zip)
        #expect(throws: ZipError.self) { try reader.data(for: "bomb.bin") }
    }
}
