import Foundation
import Testing
@testable import NotchTuneCore

struct WorkspaceNameResolverTests {
    @Test
    func gitBranchReadsNormalRepositoryHead() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }

        let git = repo.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try "ref: refs/heads/feat/v8-engineering\n".write(
            to: git.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "feat/v8-engineering")
    }

    @Test
    func gitBranchReadsGitdirFileForWorktree() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let worktree = root.appendingPathComponent("worktree")
        let gitdir = root.appendingPathComponent("repo.git/worktrees/feature")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitdir, withIntermediateDirectories: true)
        try "gitdir: \(gitdir.path)\n".write(
            to: worktree.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        try "ref: refs/heads/feature/ui\n".write(
            to: gitdir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        #expect(WorkspaceNameResolver.gitBranch(for: worktree.path) == "feature/ui")
    }

    @Test
    func gitBranchPrefersClaudeWorktreePathBranch() throws {
        let cwd = "/tmp/open-island/.claude/worktrees/feat+v8-design"

        #expect(WorkspaceNameResolver.gitBranch(for: cwd) == "feat/v8-design")
    }

    @Test
    func gitBranchCachesResultAcrossRepeatedLookups() throws {
        // Pins the SwiftUI layout-loop fix: repeated lookups for the
        // same cwd must hit the in-memory cache instead of re-walking
        // the directory tree. Demonstrated by mutating HEAD between
        // calls — without the cache the second call would surface the
        // new branch immediately. With it, the cached value persists
        // until the cache is dropped.
        WorkspaceNameResolver.resetGitBranchCacheForTests()
        defer { WorkspaceNameResolver.resetGitBranchCacheForTests() }

        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }

        let git = repo.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        let headURL = git.appendingPathComponent("HEAD")
        try "ref: refs/heads/cached-branch\n".write(to: headURL, atomically: true, encoding: .utf8)

        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "cached-branch")

        // Mutate underlying HEAD; cache must mask the change.
        try "ref: refs/heads/changed-branch\n".write(to: headURL, atomically: true, encoding: .utf8)
        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "cached-branch")

        // After the cache is dropped the new branch is observed.
        WorkspaceNameResolver.resetGitBranchCacheForTests()
        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "changed-branch")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceNameResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
