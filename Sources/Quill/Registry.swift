import CryptoKit
import Foundation

enum Registry {
    static let source = URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json")!

    struct Catalog: Decodable { var agents: [Entry] }

    struct Entry: Decodable {
        var id: String
        var distribution: Distribution
    }

    struct Distribution: Decodable {
        var npx: Package?
        var binary: [String: Archive]?
    }

    struct Package: Decodable {
        var package: String
        var args: [String]?
    }

    struct Archive: Decodable {
        var archive: URL
        var cmd: String
        var args: [String]?
        var sha256: String?
    }

    struct Unavailable: LocalizedError {
        var errorDescription: String?
    }

    static var platform: String {
        #if arch(arm64)
        "darwin-aarch64"
        #else
        "darwin-x86_64"
        #endif
    }

    static var cache: URL { Ledger.dir.appending(path: "agents") }
    @MainActor static var status: ((String) -> Void)?

    @MainActor static func argv(_ id: String, local: [String]?) async throws -> [String] {
        if let local, await Shell.find(local[0]) != nil { return local }
        guard let entry = try await catalog().agents.first(where: { $0.id == id }) else {
            throw Unavailable(errorDescription: "\(id) is not in the ACP registry.")
        }
        if let archive = entry.distribution.binary?[platform] {
            return [try await install(id, archive).path] + (archive.args ?? [])
        }
        if let npx = entry.distribution.npx {
            return ["npx", "-y", npx.package] + (npx.args ?? [])
        }
        throw Unavailable(errorDescription: "\(id) has no build for this Mac.")
    }

    private static func catalog() async throws -> Catalog {
        let saved = cache.appending(path: "registry.json")
        let age = (try? saved.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { -$0.timeIntervalSinceNow } ?? .infinity
        if age > 86_400 {
            if let (data, _) = try? await URLSession.shared.data(from: source), (try? JSONDecoder().decode(Catalog.self, from: data)) != nil {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                try data.write(to: saved, options: .atomic)
            }
        }
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: saved))
    }

    @MainActor private static func install(_ id: String, _ archive: Archive) async throws -> URL {
        let folder = cache.appending(path: id).appending(path: archive.sha256 ?? archive.archive.deletingPathExtension().lastPathComponent)
        let command = folder.appending(path: archive.cmd).standardizedFileURL
        if FileManager.default.isExecutableFile(atPath: command.path) { return command }
        status?("Downloading the co-writer, once")
        let (download, _) = try await URLSession.shared.download(from: archive.archive)
        if let sha = archive.sha256 {
            let digest = SHA256.hash(data: try Data(contentsOf: download)).map { String(format: "%02x", $0) }.joined()
            guard digest == sha.lowercased() else { throw Unavailable(errorDescription: "The \(id) download did not match its checksum.") }
        }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let unpack = Process()
        let name = archive.archive.lastPathComponent
        if name.hasSuffix(".zip") {
            unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unpack.arguments = ["-x", "-k", download.path, folder.path]
        } else {
            unpack.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            unpack.arguments = ["-xf", download.path, "-C", folder.path]
        }
        try unpack.run()
        unpack.waitUntilExit()
        guard unpack.terminationStatus == 0, FileManager.default.fileExists(atPath: command.path) else {
            throw Unavailable(errorDescription: "Could not unpack \(id).")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
        return command
    }
}
