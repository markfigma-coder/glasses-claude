import SwiftUI
import MWDATCore

@main
struct GlassesClaudeApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var assistant: Assistant

    init() {
        // SDK Meta нужно сконфигурировать один раз до любых других вызовов
        do {
            try Wearables.configure()
        } catch {
            print("Wearables.configure failed: \(error)")
        }
        let library = LibraryStore()
        _library = StateObject(wrappedValue: library)
        _assistant = StateObject(wrappedValue: Assistant(library: library))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(assistant: assistant,
                        glasses: assistant.glasses,
                        voice: assistant.voice,
                        settings: AppSettings.shared,
                        library: library)
                .onOpenURL { url in
                    // Возврат из Meta AI app после регистрации / выдачи разрешения
                    Task { await assistant.glasses.handle(url: url) }
                }
        }
    }
}
