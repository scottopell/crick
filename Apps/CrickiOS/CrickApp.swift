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
            let store = try FileSnapshotStore.applicationSupport()
            let session = try SimulationSession(snapshotStore: store)
            return AnyView(ContentView(session: session))
        } catch {
            return AnyView(ContentUnavailableView(
                "Crick could not start",
                systemImage: "exclamationmark.triangle",
                description: Text(String(describing: error))
            ))
        }
    }
}
