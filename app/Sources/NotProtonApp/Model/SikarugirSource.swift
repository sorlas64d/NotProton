// Finds Sikarugir's engines and Template on disk and checks the engines for support

import Foundation

enum SikarugirSupport: Sendable, Equatable {
    case supported(RunnerBuild)
    case unsupportedEngine
    case unreadable
}

// An engine archive in Sikarugir's Engines folder, as Sikarugir downloaded it.
struct SikarugirEngine: Sendable, Identifiable, Equatable {
    let archive: URL
    let support: SikarugirSupport

    var id: String { archive.path(percentEncoded: false) }

    var name: String {
        archive.lastPathComponent.replacingOccurrences(of: SikarugirSource.archiveSuffix, with: "")
    }

    var build: RunnerBuild? {
        if case .supported(let build) = support { return build }
        return nil
    }

    var isUsable: Bool { build != nil }
}

struct SikarugirInstall: Sendable, Equatable {
    let engines: [SikarugirEngine]

    // The newest Template's Frameworks, which the engine cannot run without. Sikarugir
    // replaces the Template when it updates, so a runner copies these rather than
    // pointing at them.
    let frameworks: URL?

    var isPresent: Bool { !engines.isEmpty || frameworks != nil }

    var usableEngines: [SikarugirEngine] { engines.filter(\.isUsable) }

    static let none = SikarugirInstall(engines: [], frameworks: nil)
}

enum SikarugirSource {

    static let archiveSuffix = ".tar.xz"

    // The library wineserver links against, so a Frameworks folder without it is not one the
    // engine can start from.
    static let requiredFramework = "libinotify.0.dylib"

    // Beside Frameworks in a Template's Contents, and in a runner the same way.
    static let vulkanManifests = "Resources/vulkan"

    static var defaultRoot: URL { SupportPaths.applicationSupport.appending(path: "Sikarugir") }

    static func discover(root: URL = defaultRoot) -> SikarugirInstall {
        let engines = engineArchives(in: root)
            .map(inspect(archive:))
            .sorted(by: preferred)
        return SikarugirInstall(engines: engines, frameworks: frameworks(in: root))
    }

    static func engineArchives(in root: URL) -> [URL] {
        let folder = root.appending(path: "Engines")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return entries.filter { $0.lastPathComponent.hasSuffix(archiveSuffix) }
    }

    static func inspect(archive: URL) -> SikarugirEngine {
        guard let hash = archiveHash(archive) else {
            return SikarugirEngine(archive: archive, support: .unreadable)
        }
        guard let build = SupportedRunners.build(engineArchiveSHA256: hash) else {
            return SikarugirEngine(archive: archive, support: .unsupportedEngine)
        }
        return SikarugirEngine(archive: archive, support: .supported(build))
    }

    // Usable first, then the newest pinned revision, so the default is the best engine there.
    static func preferred(_ a: SikarugirEngine, _ b: SikarugirEngine) -> Bool {
        if a.isUsable != b.isUsable { return a.isUsable }
        if let x = a.build, let y = b.build, x.id != y.id {
            return x.id.compare(y.id, options: .numeric) == .orderedDescending
        }
        return a.name < b.name
    }

    static func frameworks(in root: URL) -> URL? {
        let folder = root.appending(path: "Template")
        let templates = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasPrefix("Template-") && $0.pathExtension == "app" }

        let newest = templates.max {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending
        }
        guard let frameworks = newest?.appending(path: "Contents/Frameworks"),
              FileManager.default.fileExists(
                  atPath: frameworks.appending(path: requiredFramework).path(percentEncoded: false)
              )
        else { return nil }
        return frameworks
    }

    // An engine archive is about 160 MB, and the status page refreshes often, so a hash is
    // kept for as long as the file's size and modification date say it is the same file.
    private final class HashCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: (size: Int, modified: Date, hash: String)] = [:]

        func hash(for url: URL, compute: (URL) -> String?) -> String? {
            let path = url.path(percentEncoded: false)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? Int,
                  let modified = attributes[.modificationDate] as? Date
            else { return nil }

            lock.lock()
            let cached = entries[path]
            lock.unlock()
            if let cached, cached.size == size, cached.modified == modified { return cached.hash }

            guard let hash = compute(url) else { return nil }
            lock.lock()
            entries[path] = (size, modified, hash)
            lock.unlock()
            return hash
        }
    }

    private static let cache = HashCache()

    static func archiveHash(_ archive: URL) -> String? {
        cache.hash(for: archive) { Digest.sha256IfPresent($0) }
    }
}
