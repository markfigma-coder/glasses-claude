import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $settings.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Ключ Claude API")
                } footer: {
                    Text("platform.claude.com → API Keys. Хранится только на этом iPhone, в Keychain.")
                }

                Section("Модель") {
                    Picker("Модель", selection: $settings.model) {
                        ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Toggle("Отвечать только на «Клод, …»", isOn: $settings.requireWakeWord)
                } header: {
                    Text("Голос")
                } footer: {
                    Text(settings.requireWakeWord
                         ? "Отвечаю только на фразы со словом «Клод». Тап по сфере — отправить следующую фразу без него."
                         : "Отвечаю на любую фразу после паузы. Удобно в тишине, но могу реагировать на чужую речь.")
                }

                Section {
                    Toggle("Слушать микрофонами очков", isOn: $settings.useGlassesMic)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Скорость речи")
                        Slider(value: $settings.speechRate, in: 0.4...0.6)
                    }
                } footer: {
                    Text("Если выключить микрофоны очков, слушаю через iPhone, а голос ответа в очках звучит чище. После изменения перезапусти голос.")
                }

                if GlassesManager.cameraEnabled {
                    Section("Кадр с камеры очков") {
                        Picker("Кадр", selection: $settings.imageMode) {
                            ForEach(ImageMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section {
                    Button("Начать новую тему") {
                        library.startNewTopic()
                        dismiss()
                    }
                    Button("Удалить всю историю и папки", role: .destructive) {
                        confirmWipe = true
                    }
                } header: {
                    Text("История")
                } footer: {
                    Text("\(RU.topics(library.topics.count)), папок: \(library.folders.count). Если 30 минут не общаться, новая тема начнётся сама.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .confirmationDialog("Удалить всю историю?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Удалить всё", role: .destructive) { library.deleteEverything() }
            } message: {
                Text("Все темы, сообщения и папки удалятся с iPhone без возможности восстановления.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
