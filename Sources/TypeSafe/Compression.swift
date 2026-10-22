import Foundation
import CZlib

/// Request body compression, sent as `Content-Encoding`.
public enum RequestCompression: String, Sendable, CaseIterable {
    /// Compress bodies of 1 KiB or more with gzip.
    case gzip
    /// Send every body uncompressed, for example to an API that doesn't accept compressed requests.
    case off
}

/// Bodies smaller than this fit in a single TCP segment, so they are sent uncompressed.
let compressionThreshold = 1024

func gzip(_ data: Data) throws -> Data {
    var stream = z_stream()
    // MAX_WBITS + 16 makes deflate write a gzip header and trailer instead of a zlib wrapper.
    var status = deflateInit2_(
        &stream,
        Z_DEFAULT_COMPRESSION,
        Z_DEFLATED,
        MAX_WBITS + 16,
        8,
        Z_DEFAULT_STRATEGY,
        ZLIB_VERSION,
        Int32(MemoryLayout<z_stream>.size)
    )
    guard status == Z_OK else {
        throw TypeSafeError(message: "gzip compression failed to start (\(status)).")
    }
    defer { deflateEnd(&stream) }

    var output = Data(count: Int(deflateBound(&stream, uLong(data.count))))
    data.withUnsafeBytes { input in
        output.withUnsafeMutableBytes { buffer in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(buffer.count)
            status = deflate(&stream, Z_FINISH)
        }
    }
    guard status == Z_STREAM_END else {
        throw TypeSafeError(message: "gzip compression failed (\(status)).")
    }
    output.count = Int(stream.total_out)
    return output
}
