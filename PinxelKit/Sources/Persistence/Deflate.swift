import Compression
import Foundation

/// Raw DEFLATE (RFC 1951), ZIP method 8. In Compression it is called `.zlib`.
enum Deflate {
    static func compress(_ data: Data) throws -> Data {
        var output = Data()
        let filter = try OutputFilter(.compress, using: .zlib) { chunk in
            if let chunk { output.append(chunk) }
        }
        try filter.write(data)
        try filter.finalize()
        return output
    }

    /// Stops as soon as the output exceeds `limit` bytes (zip bomb protection).
    static func decompress(_ data: Data, limit: Int) throws -> Data {
        var output = Data()
        output.reserveCapacity(min(limit, 64 * 1024 * 1024))
        var exceeded = false
        let filter = try OutputFilter(.decompress, using: .zlib) { chunk in
            guard let chunk, !exceeded else { return }
            if output.count + chunk.count > limit {
                exceeded = true
                return
            }
            output.append(chunk)
        }
        try filter.write(data)
        try filter.finalize()
        if exceeded { throw ZipError.entryTooLarge("decompressed data exceeds the declared size") }
        return output
    }
}
