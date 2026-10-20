import Foundation

public enum ZipError: Error, Equatable {
    case corrupt(String)
    case unsafeEntryName(String)
    case tooManyEntries(Int)
    case entryTooLarge(String)
    case archiveTooLarge
    case unsupportedMethod(UInt16)
    case encrypted
    case checksumMismatch(String)
    case missingEntry(String)
}

public struct ZipLimits: Sendable {
    public var maxEntries: Int
    public var maxTotalUncompressedSize: Int

    public init(maxEntries: Int = 1000, maxTotalUncompressedSize: Int = 2 * 1024 * 1024 * 1024) {
        self.maxEntries = maxEntries
        self.maxTotalUncompressedSize = maxTotalUncompressedSize
    }

    public static let `default` = ZipLimits()
}

private enum Signature {
    static let localHeader: UInt32 = 0x0403_4B50
    static let centralHeader: UInt32 = 0x0201_4B50
    static let endOfCentralDirectory: UInt32 = 0x0605_4B50
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }
}

/// Minimal ZIP writer (no ZIP64, no encryption). Names in UTF-8.
public struct ZipWriter {
    public enum Method: UInt16 {
        case store = 0
        case deflate = 8
    }

    private var output = Data()
    private var central = Data()
    private var count = 0

    public init() {}

    public mutating func add(name: String, data: Data, method: Method) throws {
        let nameBytes = Data(name.utf8)
        let crc = CRC32.checksum(data)
        var payload = data
        var actualMethod = Method.store
        if method == .deflate, let compressed = try? Deflate.compress(data), compressed.count < data.count {
            payload = compressed
            actualMethod = .deflate
        }
        guard data.count < Int(UInt32.max), payload.count < Int(UInt32.max), output.count < Int(UInt32.max),
              nameBytes.count < Int(UInt16.max) else { throw ZipError.archiveTooLarge }
        let offset = UInt32(output.count)
        let dosDate: UInt16 = 0x21 // 1 January 1980

        output.appendUInt32(Signature.localHeader)
        output.appendUInt16(20)            // version needed
        output.appendUInt16(0x0800)        // flag: UTF-8 names
        output.appendUInt16(actualMethod.rawValue)
        output.appendUInt16(0)             // time
        output.appendUInt16(dosDate)
        output.appendUInt32(crc)
        output.appendUInt32(UInt32(payload.count))
        output.appendUInt32(UInt32(data.count))
        output.appendUInt16(UInt16(nameBytes.count))
        output.appendUInt16(0)             // extra
        output.append(nameBytes)
        output.append(payload)

        central.appendUInt32(Signature.centralHeader)
        central.appendUInt16(20)           // creator version
        central.appendUInt16(20)           // version needed
        central.appendUInt16(0x0800)
        central.appendUInt16(actualMethod.rawValue)
        central.appendUInt16(0)
        central.appendUInt16(dosDate)
        central.appendUInt32(crc)
        central.appendUInt32(UInt32(payload.count))
        central.appendUInt32(UInt32(data.count))
        central.appendUInt16(UInt16(nameBytes.count))
        central.appendUInt16(0)            // extra
        central.appendUInt16(0)            // comment
        central.appendUInt16(0)            // disk
        central.appendUInt16(0)            // internal attributes
        central.appendUInt32(0)            // external attributes
        central.appendUInt32(offset)
        central.append(nameBytes)
        count += 1
    }

    public mutating func finish() throws -> Data {
        guard count < Int(UInt16.max) else { throw ZipError.tooManyEntries(count) }
        guard output.count + central.count < Int(UInt32.max) else { throw ZipError.archiveTooLarge }
        var result = output
        let centralOffset = UInt32(result.count)
        result.append(central)
        result.appendUInt32(Signature.endOfCentralDirectory)
        result.appendUInt16(0)
        result.appendUInt16(0)
        result.appendUInt16(UInt16(count))
        result.appendUInt16(UInt16(count))
        result.appendUInt32(UInt32(central.count))
        result.appendUInt32(centralOffset)
        result.appendUInt16(0)
        return result
    }
}

public struct ZipEntry: Equatable, Sendable {
    public let name: String
    public let uncompressedSize: Int
    let method: UInt16
    let crc: UInt32
    let compressedSize: Int
    let localHeaderOffset: Int
}

/// Defensive ZIP reader: validates names, entry count, declared sizes and checksum.
public struct ZipReader {
    public let entries: [ZipEntry]
    private let reader: ByteReader

    public init(_ data: Data, limits: ZipLimits = .default) throws {
        let reader = ByteReader(data)
        self.reader = reader
        let end = try Self.findEndOfCentralDirectory(reader)
        let total = Int(try reader.uint16(at: end + 10))
        let centralSize = Int(try reader.uint32(at: end + 12))
        let centralOffset = Int(try reader.uint32(at: end + 16))
        guard total <= limits.maxEntries else { throw ZipError.tooManyEntries(total) }
        guard centralOffset + centralSize <= end else { throw ZipError.corrupt("central directory out of bounds") }

        var entries: [ZipEntry] = []
        var names = Set<String>()
        var totalSize = 0
        var offset = centralOffset
        for _ in 0..<total {
            guard try reader.uint32(at: offset) == Signature.centralHeader else {
                throw ZipError.corrupt("bad central directory entry at \(offset)")
            }
            let flags = try reader.uint16(at: offset + 8)
            let method = try reader.uint16(at: offset + 10)
            let crc = try reader.uint32(at: offset + 16)
            let compressedSize = Int(try reader.uint32(at: offset + 20))
            let uncompressedSize = Int(try reader.uint32(at: offset + 24))
            let nameLength = Int(try reader.uint16(at: offset + 28))
            let extraLength = Int(try reader.uint16(at: offset + 30))
            let commentLength = Int(try reader.uint16(at: offset + 32))
            let localHeaderOffset = Int(try reader.uint32(at: offset + 42))
            guard let name = String(data: try reader.bytes(at: offset + 46, count: nameLength), encoding: .utf8) else {
                throw ZipError.unsafeEntryName("<non-UTF-8>")
            }
            if flags & 0x1 != 0 { throw ZipError.encrypted }
            guard method == 0 || method == 8 else { throw ZipError.unsupportedMethod(method) }
            try Self.validate(name: name)
            guard names.insert(name).inserted else { throw ZipError.corrupt("duplicate entry \(name)") }
            totalSize += uncompressedSize
            guard totalSize <= limits.maxTotalUncompressedSize else { throw ZipError.entryTooLarge(name) }
            entries.append(ZipEntry(
                name: name, uncompressedSize: uncompressedSize, method: method, crc: crc,
                compressedSize: compressedSize, localHeaderOffset: localHeaderOffset
            ))
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    public func data(for name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw ZipError.missingEntry(name) }
        return try data(for: entry)
    }

    public func data(for entry: ZipEntry) throws -> Data {
        let offset = entry.localHeaderOffset
        guard try reader.uint32(at: offset) == Signature.localHeader else {
            throw ZipError.corrupt("bad local header for \(entry.name)")
        }
        let nameLength = Int(try reader.uint16(at: offset + 26))
        let extraLength = Int(try reader.uint16(at: offset + 28))
        let payload = try reader.bytes(at: offset + 30 + nameLength + extraLength, count: entry.compressedSize)
        let result: Data
        if entry.method == 0 {
            result = payload
        } else {
            do {
                result = try Deflate.decompress(payload, limit: entry.uncompressedSize)
            } catch let error as ZipError {
                throw error
            } catch {
                throw ZipError.corrupt("invalid deflate data in \(entry.name)")
            }
        }
        guard result.count == entry.uncompressedSize else { throw ZipError.corrupt("size mismatch for \(entry.name)") }
        guard CRC32.checksum(result) == entry.crc else { throw ZipError.checksumMismatch(entry.name) }
        return result
    }

    static func validate(name: String) throws {
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        if name.isEmpty || name.hasPrefix("/") || name.contains("\\") || name.contains("\0")
            || components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            throw ZipError.unsafeEntryName(name)
        }
    }

    private static func findEndOfCentralDirectory(_ reader: ByteReader) throws -> Int {
        let minimumSize = 22
        guard reader.count >= minimumSize else { throw ZipError.corrupt("file too small") }
        let lowest = max(0, reader.count - minimumSize - 65_535)
        var offset = reader.count - minimumSize
        while offset >= lowest {
            if try reader.uint32(at: offset) == Signature.endOfCentralDirectory { return offset }
            offset -= 1
        }
        throw ZipError.corrupt("end of central directory not found")
    }
}
