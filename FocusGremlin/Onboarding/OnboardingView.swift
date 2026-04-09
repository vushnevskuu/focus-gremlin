import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Focus Gremlin")
                    .font(.largeTitle.bold())
                Text("Локальный спутник, который мягко подкалывает, когда ты увлекаешься не тем экраном. Данные не уходят в облако.")
                    .foregroundStyle(.secondary)

                GroupBox("Accessibility") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Нужен, чтобы прочитать заголовок активного окна и лучше понимать контекст браузера. Без доступа приложение всё равно работает по bundle ID, но хуже отличает «рабочую» вкладку от ленты.")
                        Button("Открыть системные настройки") {
                            PermissionGate.openPrivacyPane(anchor: "Accessibility")
                        }
                    }
                }

                GroupBox("Мониторинг ввода (опционально)") {
                    Text("Глобальный скролл-детектор использует системный монитор событий. Если macOS попросит — добавьте Focus Gremlin в список «Мониторинг ввода». Без этого останется детекция по времени и alt-tab паттернам.")
                }

                GroupBox("Запись экрана (Smart Mode)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Если включите Smart Mode в настройках, приложение редко снимает экран в память и отправляет сжатый кадр только в локальную Ollama с vision-моделью. По умолчанию на диск не сохраняется; опция отладки — отдельный переключатель.")
                        Button("Запросить доступ к записи экрана") {
                            _ = PermissionGate.requestScreenCaptureAccess()
                        }
                    }
                }

                GroupBox("Как это устроено") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Оверлей — это `NSPanel`: не крадёт фокус и по умолчанию пропускает клики.")
                        Text("• Курсор отслеживается локально, без сети.")
                        Text("• Фразы — шаблоны + опционально Ollama на localhost.")
                    }
                    .font(.body)
                }

                Spacer(minLength: 12)

                HStack {
                    Spacer()
                    Button("Начать пользоваться") {
                        settings.onboardingCompleted = true
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 640)
    }
}
