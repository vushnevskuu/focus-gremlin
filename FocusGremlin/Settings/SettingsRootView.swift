import AppKit
import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var settings: SettingsStore
    /// Сбрасывает кэш SwiftUI: после выдачи прав в «Настройках» приложение снова читает AX/ScreenCapture.
    @State private var permissionRefreshToken = 0

    var body: some View {
        Form {
            Section("Агент") {
                Toggle("Включить Focus Gremlin", isOn: $settings.agentEnabled)
                Picker("Интенсивность тона", selection: $settings.toneIntensity) {
                    Text("Мягко").tag(ToneIntensity.gentle)
                    Text("Язвительно").tag(ToneIntensity.snarky)
                    Text("Вмешательство").tag(ToneIntensity.intervention)
                }
                Picker("Язык", selection: $settings.language) {
                    Text("Русский").tag(AppLanguage.ru)
                    Text("English").tag(AppLanguage.en)
                }
            }

            Section("Лимиты") {
                Stepper(value: $settings.cooldownSeconds, in: 20...600, step: 5) {
                    Text("Кулдаун: \(Int(settings.cooldownSeconds)) с")
                }
                Stepper(value: $settings.maxInterruptionsPerHour, in: 1...30) {
                    Text("Макс. вмешательств в час: \(settings.maxInterruptionsPerHour)")
                }
                Stepper(value: $settings.distractionSecondsBeforeNudge, in: 10...600, step: 5) {
                    Text("Порог отвлечения: \(Int(settings.distractionSecondsBeforeNudge)) с")
                }
            }

            Section("Списки") {
                Text("Продуктивные bundle ID (по одному в строке)")
                TextEditor(text: Binding(
                    get: { settings.productiveBundleIDs.joined(separator: "\n") },
                    set: { settings.productiveBundleIDs = $0.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty } }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)

                Text("Отвлекающие bundle ID")
                TextEditor(text: Binding(
                    get: { settings.distractingBundleIDs.joined(separator: "\n") },
                    set: { settings.distractingBundleIDs = $0.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty } }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)

                Text("Ключевые слова «работы» в заголовке вкладки")
                TextEditor(text: Binding(
                    get: { settings.browserWorkKeywords.joined(separator: "\n") },
                    set: { settings.browserWorkKeywords = $0.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty } }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70)
            }

            Section("Локальная модель (Ollama)") {
                Toggle("Использовать LLM для фраз", isOn: $settings.useLLMForLines)
                TextField("Базовый URL", text: $settings.ollamaBaseURL)
                TextField("Модель", text: $settings.ollamaModel)
                Stepper(value: $settings.llmMinIntervalSeconds, in: 30...900, step: 15) {
                    Text("Мин. интервал LLM: \(Int(settings.llmMinIntervalSeconds)) с")
                }
            }

            Section("Система") {
                Toggle("Звуки", isOn: $settings.soundEffectsEnabled)
                Toggle("Автозапуск при входе (macOS 13+)", isOn: $settings.startAtLogin)
                    .onChange(of: settings.startAtLogin) { _, newValue in
                        do {
                            try LoginItemManager.setStartAtLogin(newValue)
                        } catch {
                            settings.startAtLogin = false
                            AppLogger.app.error("Login item: \(error.localizedDescription, privacy: .public)")
                        }
                    }
            }

            Section("Smart Mode (локальная VLM)") {
                Toggle("Согласие: редкий захват экрана в память + анализ в Ollama на этом Mac", isOn: $settings.smartVisionConsent)
                Toggle("Включить Smart Mode", isOn: $settings.smartModeEnabled)
                    .disabled(!settings.smartVisionConsent)
                    .onChange(of: settings.smartModeEnabled) { _, on in
                        if on {
                            _ = PermissionGate.requestScreenCaptureAccess()
                        }
                    }
                Stepper(value: $settings.smartSamplingIntervalSeconds, in: 35...240, step: 5) {
                    Text("Интервал семплинга: \(Int(settings.smartSamplingIntervalSeconds)) с")
                }
                TextField("Vision-модель Ollama", text: $settings.smartVisionModel)
                Toggle("Сохранять последний кадр в Application Support (отладка)", isOn: $settings.smartDebugSaveFrames)
                    .disabled(!settings.smartVisionConsent)
                Button("Запросить доступ к записи экрана") {
                    _ = PermissionGate.requestScreenCaptureAccess()
                }
                Button("Настройки → Запись экрана") {
                    PermissionGate.openPrivacyPane(anchor: "ScreenCapture")
                }
                Text("Нужна vision-модель (`ollama pull llava` и т.п.). Кадры по умолчанию не пишутся на диск.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Проверка") {
                Button("Показать тестовое сообщение") {
                    Task { await CompanionSession.playTestMessage() }
                }
            }

            Section("Приватность и доступы") {
                LabeledContent("Accessibility") {
                    Text(axTrustedLabel)
                        .foregroundStyle(PermissionGate.accessibilityTrusted ? .green : .orange)
                }
                LabeledContent("Запись экрана") {
                    Text(screenLabel)
                        .foregroundStyle(PermissionGate.screenRecordingAuthorized ? .green : .orange)
                }
                Button("Открыть: Accessibility") {
                    PermissionGate.openPrivacyPane(anchor: "Accessibility")
                }
                Button("Открыть: Запись экрана") {
                    PermissionGate.openPrivacyPane(anchor: "ScreenCapture")
                }
                Button("Обновить статус") {
                    permissionRefreshToken &+= 1
                }
                Text(
                    "Если только что включил доступ: вернись в это окно и нажми «Обновить статус» или полностью закрой Focus Gremlin (⌘Q) и запусти снова. В списке должен быть именно этот билд (Debug из Xcode и .app из папки build — разные записи)."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .id(permissionRefreshToken)
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 640)
        .onAppear { permissionRefreshToken &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshToken &+= 1
        }
    }

    private var axTrustedLabel: String {
        _ = permissionRefreshToken
        return PermissionGate.accessibilityTrusted ? "Включено" : "Нужно для заголовка окна"
    }

    private var screenLabel: String {
        _ = permissionRefreshToken
        return PermissionGate.screenRecordingAuthorized ? "Разрешено" : "Нужно для Smart Mode"
    }
}
