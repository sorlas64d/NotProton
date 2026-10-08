import Foundation
import Testing

@testable import NotProtonApp

@Suite("Sikarugir runner")
struct SikarugirRunnerTests {

    private static let crossOver = SupportedRunners.builds(of: .crossOver)[0]
    private static let sikarugir = SupportedRunners.builds(of: .sikarugir)[0]

    private func scratch(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "np-sik-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Naming

    @Test("A build's kind follows from its id, so a directory alone says what it holds")
    func kindFromID() {
        for build in SupportedRunners.all {
            #expect(RunnerKind(buildID: build.id) == build.kind)
        }
        #expect(!SupportedRunners.builds(of: .sikarugir).isEmpty)
    }

    @Test("An earlier install that ran games through Sikarugir keeps the 'notproton' tool name")
    func legacyNameSurvivesForSikarugir() throws {
        let runners = try scratch("legacy")
        defer { try? FileManager.default.removeItem(at: runners) }
        try FileManager.default.createSymbolicLink(
            atPath: runners.appending(path: "current").path(percentEncoded: false),
            withDestinationPath: "\(Self.sikarugir.id)/Engine"
        )

        let holder = CompatToolList.legacyHolder(builds: [Self.sikarugir], listed: nil, runners: runners)
        #expect(holder == .build(Self.sikarugir.id))
        let tools = SupportedRunners.tools(for: [Self.sikarugir], legacy: holder)
        #expect(tools.map(\.name) == [SupportedRunners.legacyToolName])
    }

    @Test("Installing into Steam gives a Sikarugir runner the Sikarugir lsteamclient, not CrossOver's")
    func deploymentUsesSikarugirBridge() throws {
        let runners = try scratch("deploy")
        defer { try? FileManager.default.removeItem(at: runners) }
        let none = URL(filePath: "/none")
        let payload = InstallPayload.Located(
            dylib: none, overlayShim: none, iconmaker: none, appinfo: none, run: none, builtAt: 0, signatures: []
        )
        let crossOverSource = URL(filePath: "/payload/crossover-unix")
        let sikarugirSource = URL(filePath: "/payload/sikarugir-unix")
        let bridge = BridgePayload.Located(sources: [
            (crossOverSource, ["x86_64-unix/lsteamclient.so"]),
            (sikarugirSource, ["\(RunnerPatcher.sikarugirBridgeDirectory)/x86_64-unix/lsteamclient.so"]),
        ])
        let tools = SupportedRunners.tools(for: [Self.crossOver, Self.sikarugir])

        let files = DeploymentContent.files(
            payload: payload, bridgePayload: bridge, app: none, bridge: none, signatures: none,
            overlayShim: none, iconmaker: none, appinfo: none, compatTools: none, tools: tools, runners: runners
        )
        func source(of build: RunnerBuild) -> URL? {
            let destination = SupportPaths.clonedRoot(forBuild: build.id, runners: runners)
                .appending(path: "lib/wine/x86_64-unix/lsteamclient.so")
            return files.first { $0.destination == destination }?.source
        }
        #expect(source(of: Self.crossOver) == crossOverSource)
        #expect(source(of: Self.sikarugir) == sikarugirSource)
    }

    @Test("CrossOver keeps its directory names and Sikarugir gets its own")
    func directoryNames() {
        let runners = URL(filePath: "/runners")
        #expect(SupportPaths.runnerRoot(forBuild: Self.crossOver.id, runners: runners).lastPathComponent
            == "crossover-\(Self.crossOver.id)")
        #expect(SupportPaths.clonedRoot(forBuild: Self.crossOver.id, runners: runners).lastPathComponent
            == "CrossOver")
        #expect(SupportPaths.runnerRoot(forBuild: Self.sikarugir.id, runners: runners).lastPathComponent
            == Self.sikarugir.id)
        #expect(SupportPaths.clonedRoot(forBuild: Self.sikarugir.id, runners: runners).lastPathComponent
            == "Engine")
    }

    @Test("The store reads both kinds of build back from runners")
    func storeReadsBothKinds() throws {
        let runners = try scratch("store")
        defer { try? FileManager.default.removeItem(at: runners) }

        for build in [Self.crossOver, Self.sikarugir] {
            try FileManager.default.createDirectory(
                at: SupportPaths.clonedRoot(forBuild: build.id, runners: runners).appending(path: "lib/wine"),
                withIntermediateDirectories: true
            )
        }
        // A staging directory and anything else under runners/ is not a build.
        try FileManager.default.createDirectory(
            at: runners.appending(path: ".\(Self.sikarugir.id).new"), withIntermediateDirectories: true
        )

        #expect(Set(RunnerStore.clonedBuilds(in: runners)) == [Self.crossOver.id, Self.sikarugir.id])
        #expect(Set(RunnerStore.installedBuilds(in: runners).map(\.id)) == [Self.crossOver.id, Self.sikarugir.id])
    }

    // MARK: - Identity

    @Test("A Sikarugir loader is never taken for a CrossOver build")
    func loaderLookupIsCrossOverOnly() {
        for build in SupportedRunners.builds(of: .sikarugir) {
            #expect(SupportedRunners.build(loaderSHA256: build.loaderSHA256) == nil)
            #expect(build.engineArchiveSHA256 != nil)
            #expect(SupportedRunners.build(engineArchiveSHA256: build.engineArchiveSHA256!) == build)
        }
        for build in SupportedRunners.builds(of: .crossOver) {
            #expect(build.engineArchiveSHA256 == nil)
        }
        #expect(!SupportedRunners.versionList.contains("revision"))
    }

    // MARK: - Discovery

    private func makeTemplate(_ name: String, in root: URL, complete: Bool = true) throws {
        let frameworks = root.appending(path: "Template/\(name)/Contents/Frameworks")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        if complete {
            try Data().write(to: frameworks.appending(path: SikarugirSource.requiredFramework))
        }
    }

    @Test("The newest Template is chosen by version, and one without the libraries is not one")
    func templateChoice() throws {
        let root = try scratch("template")
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(SikarugirSource.frameworks(in: root) == nil)

        try makeTemplate("Template-1.0.9.app", in: root)
        try makeTemplate("Template-1.0.21.app", in: root)
        #expect(SikarugirSource.frameworks(in: root)?.pathComponents.contains("Template-1.0.21.app") == true)

        try makeTemplate("Template-1.0.30.app", in: root, complete: false)
        #expect(SikarugirSource.frameworks(in: root) == nil)
    }

    @Test("An engine archive that is not pinned is found and refused")
    func unpinnedArchive() throws {
        let root = try scratch("engines")
        defer { try? FileManager.default.removeItem(at: root) }

        let engines = root.appending(path: "Engines")
        try FileManager.default.createDirectory(at: engines, withIntermediateDirectories: true)
        try Data("not an engine".utf8).write(to: engines.appending(path: "WS12WineOther1.0.tar.xz"))
        try Data().write(to: engines.appending(path: "notes.txt"))

        let found = SikarugirSource.discover(root: root)
        #expect(found.engines.count == 1)
        #expect(found.engines[0].name == "WS12WineOther1.0")
        #expect(found.engines[0].support == .unsupportedEngine)
        #expect(found.usableEngines.isEmpty)
        #expect(found.isPresent)

        #expect(throws: StepFailure.self) {
            try RunnerInstaller.install(sikarugir: found.engines[0], frameworks: root, runners: root)
        }
    }

    // MARK: - Setup

    @Test("A Sikarugir build is set up without a CrossOver license, which it has none of")
    func noLicenseForSikarugir() throws {
        let runners = try scratch("license")
        defer { try? FileManager.default.removeItem(at: runners) }
        for build in [Self.crossOver, Self.sikarugir] {
            try FileManager.default.createDirectory(
                at: SupportPaths.clonedRoot(forBuild: build.id, runners: runners).appending(path: "lib/wine"),
                withIntermediateDirectories: true
            )
        }

        func prepare(_ build: RunnerBuild) throws {
            _ = try RunnerSetup.prepare(
                build, runners: runners, bridge: runners.appending(path: "bridge"),
                toolList: runners.appending(path: "tools"),
                compatTools: runners.appending(path: "compatibilitytools.d"),
                runScript: {
                    let script = runners.appending(path: "payload-run")
                    try Data("#!/bin/sh\n".utf8).write(to: script)
                    return script
                },
                license: { _ in
                    CrossOverLicense.Status(licensed: false, detail: "not activated", diagnostic: "test")
                },
                verify: { _, _ in }, stage: { _, _, _ in [] }, patch: { _, _, _ in RunnerPatcher.Outcome() }
            )
        }

        try prepare(Self.sikarugir)
        #expect(throws: StepFailure.self) { try prepare(Self.crossOver) }
    }

    @Test("Each kind installs the lsteamclient built for its wine")
    func builtinSource() {
        let bridge = URL(filePath: "/bridge")
        #expect(RunnerPatcher.builtinSource(for: .crossOver, in: bridge) == bridge)
        #expect(RunnerPatcher.builtinSource(for: .sikarugir, in: bridge) == bridge.appending(path: "sikarugir"))
    }

    // MARK: - Payload

    @Test("The Sikarugir lsteamclient is optional in the app, and only a Sikarugir runner misses it")
    func optionalBridge() throws {
        let work = try scratch("bridge")
        defer { try? FileManager.default.removeItem(at: work) }

        for entry in BridgePayload.entries where entry.required {
            try Data(repeating: 1, count: 64).write(to: work.appending(path: entry.resource))
        }
        let located = try BridgePayload.locate(root: work)
        #expect(located.sources.count == BridgePayload.entries.filter(\.required).count)
        #expect(BridgePayload.entries.contains { !$0.required })

        let empty = work.appending(path: "empty-bridge")
        let forCrossOver = PayloadInspector.inspect(bridge: empty, builds: [Self.crossOver])
        let forSikarugir = PayloadInspector.inspect(bridge: empty, builds: [Self.sikarugir])
        #expect(!forCrossOver.missing.contains { $0.path.hasPrefix("sikarugir/") })
        #expect(forSikarugir.missing.contains { $0.path.hasPrefix("sikarugir/") })
    }

    @Test("Prefix tools give a Sikarugir runner the environment its engine needs, and CrossOver none of it")
    func prefixToolEnvironment() throws {
        let work = try scratch("tools")
        defer { try? FileManager.default.removeItem(at: work) }
        let prefix = WinePrefix(appID: "480", name: nil, library: SteamLibrary(root: work), lastUsed: nil)

        let crossOver = work.appending(path: "crossover")
        try FileManager.default.createDirectory(at: crossOver.appending(path: "bin"), withIntermediateDirectories: true)
        let plain = PrefixTools.environment(prefix: prefix, runner: crossOver)
        #expect(plain["SikarugirAppWine11"] == nil)
        #expect(plain["DYLD_FALLBACK_LIBRARY_PATH"] == ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"])

        let engine = work.appending(path: "engine")
        try FileManager.default.createDirectory(
            at: engine.appending(path: RunnerKind.frameworksDirectory), withIntermediateDirectories: true
        )
        #expect(RunnerKind.of(root: engine) == .sikarugir)
        let environment = PrefixTools.environment(prefix: prefix, runner: engine)
        #expect(environment["SikarugirAppWine11"] == "1")
        #expect(environment["DYLD_FALLBACK_LIBRARY_PATH"]?.hasPrefix(
            engine.appending(path: "Frameworks").path(percentEncoded: false)
        ) == true)
    }

    // MARK: - Agreement with the run script

    private static func compatSource() throws -> String {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()  // NotProtonAppTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // app
            .deletingLastPathComponent()  // repo root
        return try String(
            contentsOf: repoRoot.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
    }

    // The script picks a runner's kind by the same folder RunnerKind.of(root:) looks for.
    @Test("The run script and the app agree on what makes a Sikarugir runner")
    func runScriptAgrees() throws {
        let source = try Self.compatSource()
        for kind in [RunnerKind.crossOver, .sikarugir] {
            #expect(source.contains("runner_kind=\(kind == .sikarugir ? "sikarugir" : "crossover")\n"))
        }
        #expect(source.contains("if [ -d \"$CX_ROOT/\(RunnerKind.frameworksDirectory)\" ]; then"))
        #expect(source.contains("lsteam_rel=\"\(RunnerPatcher.sikarugirBridgeDirectory)/\""))
        #expect(source.contains("export SikarugirAppWine11=1"))
        // The renderers ship in the Frameworks copy, and DXVK's driver manifests beside it.
        #expect(source.contains("renderers=\"$CX_ROOT/\(RunnerKind.frameworksDirectory)/renderer\""))
        #expect(source.contains("manifest=\"$CX_ROOT/\(SikarugirSource.vulkanManifests)/icd.d/"))
    }

    // MARK: - Against the real thing

    // The engine is unpacked from the archive Sikarugir downloaded, so a machine with a pinned
    // one installs a real runner here, and the Swift patcher has to reproduce the hashes the
    // python patcher recorded. Without one the test has nothing to check and skips.
    @Test("A pinned engine installs into a runner whose ntdlls patch to the recorded hashes")
    func realEngineInstallsAndPatches() throws {
        let found = SikarugirSource.discover()
        guard let engine = found.usableEngines.first, let build = engine.build,
              let frameworks = found.frameworks
        else { return }

        let runners = try scratch("real")
        defer { try? FileManager.default.removeItem(at: runners) }

        #expect(try RunnerInstaller.install(sikarugir: engine, frameworks: frameworks, runners: runners) == build)
        let root = SupportPaths.clonedRoot(forBuild: build.id, runners: runners)
        #expect(RunnerKind.of(root: root) == .sikarugir)
        #expect(RunnerInstaller.hasClone(forBuild: build.id, runners: runners))
        for renderer in ["dxmt", "d3dmetal", "dxvk"] {
            #expect(FileManager.default.fileExists(atPath: root.appending(
                path: "\(RunnerKind.frameworksDirectory)/renderer/\(renderer)/wine").path(percentEncoded: false)))
        }
        let templateVulkan = frameworks.deletingLastPathComponent().appending(path: SikarugirSource.vulkanManifests)
        if FileManager.default.fileExists(atPath: templateVulkan.path(percentEncoded: false)) {
            #expect(FileManager.default.fileExists(atPath: root.appending(
                path: "\(SikarugirSource.vulkanManifests)/icd.d").path(percentEncoded: false)))
        }

        let bridge = runners.appending(path: "bridge")
        let staged = try NtdllPatcher.stage(build: build, runnerRoot: root, bridge: bridge)
        #expect(Set(staged) == Set(build.patchedNtdll.keys))
        for (arch, expected) in build.patchedNtdll {
            #expect(Digest.sha256IfPresent(NtdllPatcher.stagedCopy(of: arch, build: build.id, in: bridge)) == expected)
        }
    }
}
