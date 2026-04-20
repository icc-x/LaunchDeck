import Foundation
import os

/// Coordinates debounced writes of the layout and session snapshots to disk.
///
/// This type was carved out of `LauncherStore` to give the store a narrower surface —
/// previously the store owned five separate pieces of persistence state
/// (`persistenceTask`, `sessionTask`, `lastPersistedFingerprint`, `layoutMutationVersion`,
/// `sessionPersistenceError`) and ~100 lines of scheduling/debounce logic entangled with
/// unrelated UI state.
///
/// Responsibilities:
/// - Schedule a debounced write of a `LauncherLayoutSnapshot`, skipping the I/O when the
///   fingerprint hasn't changed since the last successful save.
/// - Schedule a debounced write of a `LauncherSessionSnapshot`.
/// - Expose `flushLayout()` / `flushSession()` so callers can force an immediate write
///   before app termination.
/// - Track the "mutation version" so a pending layout write that arrives after the data
///   has moved on can bail out cleanly.
///
/// All methods are `MainActor` isolated because the scheduler is written exclusively by
/// `LauncherStore`, which itself runs on the main actor.
@MainActor
final class LauncherPersistenceScheduler {
    private static let logger = Logger(subsystem: "com.icc.launchdeck", category: "Persistence")

    private let layoutPersistence: LauncherLayoutPersistence
    private let sessionPersistence: LauncherSessionPersistence

    private var layoutTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?

    /// Monotonically increasing counter bumped whenever the store mutates layout. A
    /// pending write compares its captured version against the current one and skips the
    /// write if the store has mutated further in the meantime.
    private(set) var layoutMutationVersion: UInt64 = 0

    /// Fingerprint of the last successfully written layout. Resets to `nil` on reload so
    /// that the first save after a catalog refresh always goes to disk.
    private(set) var lastPersistedFingerprint: UInt64?

    init(
        layoutPersistence: LauncherLayoutPersistence,
        sessionPersistence: LauncherSessionPersistence
    ) {
        self.layoutPersistence = layoutPersistence
        self.sessionPersistence = sessionPersistence
    }

    // MARK: - Version / reset

    /// Bump the mutation version. Call from the store after a successful layout mutation
    /// so that any in-flight debounced save for the prior version will be discarded.
    func noteLayoutMutation() {
        layoutMutationVersion &+= 1
    }

    /// Cancel in-flight debounced writes without touching disk. Call when a full reload
    /// is about to rewrite the layout on top of the current state.
    func invalidate() {
        layoutTask?.cancel()
        layoutTask = nil
        sessionTask?.cancel()
        sessionTask = nil
        lastPersistedFingerprint = nil
    }

    /// Cancel in-flight debounced writes. Called from the store's `cancelTransientTasks`.
    func cancelPending() {
        layoutTask?.cancel()
        layoutTask = nil
        sessionTask?.cancel()
        sessionTask = nil
    }

    // MARK: - Layout

    /// Schedule a debounced layout write. The `snapshot` and `fingerprint` are captured
    /// at call time so that future mutations don't affect what gets written.
    func scheduleLayoutWrite(
        snapshot: LauncherLayoutSnapshot,
        fingerprint: UInt64,
        delayNanoseconds: UInt64 = LauncherTuning.Debounce.layoutPersist,
        onSuccess: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        layoutTask?.cancel()
        let capturedVersion = layoutMutationVersion

        layoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.performLayoutWriteIfVersionMatches(
                snapshot: snapshot,
                fingerprint: fingerprint,
                expectedVersion: capturedVersion,
                onSuccess: onSuccess,
                onFailure: onFailure
            )
        }
    }

    /// Force an immediate layout write with the given snapshot. Used by
    /// `LauncherStore.flushPendingPersistence()` on scene-phase changes and app
    /// termination.
    func flushLayout(
        snapshot: LauncherLayoutSnapshot,
        fingerprint: UInt64,
        onSuccess: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async {
        await writeLayout(
            snapshot: snapshot,
            fingerprint: fingerprint,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    private func performLayoutWriteIfVersionMatches(
        snapshot: LauncherLayoutSnapshot,
        fingerprint: UInt64,
        expectedVersion: UInt64,
        onSuccess: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async {
        guard expectedVersion == layoutMutationVersion else { return }
        await writeLayout(
            snapshot: snapshot,
            fingerprint: fingerprint,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
        if expectedVersion == layoutMutationVersion {
            layoutTask = nil
        }
    }

    private func writeLayout(
        snapshot: LauncherLayoutSnapshot,
        fingerprint: UInt64,
        onSuccess: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async {
        guard fingerprint != lastPersistedFingerprint else { return }

        do {
            try await layoutPersistence.saveAsync(snapshot)
            lastPersistedFingerprint = fingerprint
            onSuccess()
        } catch {
            Self.logger.error("layout.save_failed error=\(error.localizedDescription, privacy: .public)")
            onFailure(LaunchDeckStrings.persistenceSaveFailed(error.localizedDescription))
        }
    }

    // MARK: - Session

    func scheduleSessionWrite(
        snapshot: LauncherSessionSnapshot,
        delayNanoseconds: UInt64 = LauncherTuning.Debounce.sessionPersist,
        onSuccess: @escaping @MainActor (LauncherSessionSnapshot) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        sessionTask?.cancel()

        sessionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.writeSession(snapshot: snapshot, onSuccess: onSuccess, onFailure: onFailure)
        }
    }

    func flushSession(
        snapshot: LauncherSessionSnapshot,
        onSuccess: @escaping @MainActor (LauncherSessionSnapshot) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async {
        await writeSession(snapshot: snapshot, onSuccess: onSuccess, onFailure: onFailure)
    }

    private func writeSession(
        snapshot: LauncherSessionSnapshot,
        onSuccess: @escaping @MainActor (LauncherSessionSnapshot) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async {
        do {
            try await sessionPersistence.saveAsync(snapshot)
            onSuccess(snapshot)
        } catch {
            Self.logger.error("session.save_failed error=\(error.localizedDescription, privacy: .public)")
            onFailure(LaunchDeckStrings.sessionSaveFailed(error.localizedDescription))
        }
    }

    /// Delete the persisted session.
    func deleteSession() async throws {
        sessionTask?.cancel()
        sessionTask = nil
        try await sessionPersistence.deleteAsync()
    }

    // MARK: - Loading

    func loadPersistedLayout() async throws -> LauncherLayoutSnapshot? {
        try await Task.detached(priority: .utility) { [layoutPersistence] in
            try layoutPersistence.load()
        }.value
    }

    func loadSession() -> LauncherSessionSnapshot? {
        sessionPersistence.load()
    }

    // MARK: - Storage paths (exposed for settings/diagnostics)

    var layoutStoragePath: String { layoutPersistence.storagePath }
    var sessionStoragePath: String { sessionPersistence.storagePath }
}
