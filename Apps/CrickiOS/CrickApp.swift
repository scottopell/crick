import SwiftUI

@main
struct CrickApp: App {
    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @MainActor
    private var rootView: some View {
        do {
            let legacyStore = try FileSnapshotStore.applicationSupport()
            let diggingStore = try FileSnapshotStore.diggingApplicationSupport()
            if ProcessInfo.processInfo.environment["CRICK_UI_TEST_RESET"] == "1" {
                try legacyStore.removeIfPresent()
                try diggingStore.removeIfPresent()
            }
            let legacySession = try SimulationSession(snapshotStore: legacyStore)
            let diggingSession = DiggingSession(snapshotStore: diggingStore)
            return AnyView(DiggingContentView(
                session: diggingSession,
                legacySession: legacySession
            ))
        } catch {
            return AnyView(ContentUnavailableView(
                "Crick could not start",
                systemImage: "exclamationmark.triangle",
                description: Text(String(describing: error))
            ))
        }
    }
}
