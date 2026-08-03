import Darwin
import Foundation

internal enum DNSError: Error {
    case failed
    case timeout
    case inProgress
}

internal final class DNS {
    let hostname: String

    init(hostname: String) {
        self.hostname = hostname
    }

    func lookup(timeout: TimeInterval = 10.0) throws -> [Data] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &result) == 0 else {
            throw DNSError.failed
        }
        defer { freeaddrinfo(result) }

        var addresses: [Data] = []
        var cursor = result
        while let info = cursor?.pointee {
            if let address = info.ai_addr {
                addresses.append(Data(bytes: address, count: Int(info.ai_addrlen)))
            }
            cursor = info.ai_next
        }
        guard !addresses.isEmpty else { throw DNSError.failed }
        return addresses
    }
}
