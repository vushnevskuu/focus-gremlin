import AppKit
import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var settings: SettingsStore
    /// Обновляется только по кнопке и при первом появлении — без опроса TCC на каждый кадр SwiftUI.
    @State private var axGrantedSnapshot = false
    @State private var screenGrantedSnapshot = false
    @State private var scrollMonitorActiveSnapshot = false
    @State private var lastActivePermissionRefresh = Date.distantPast
    @State private var openAIKeyDraft = ""
    @State private var anthropicKeyDraft = ""

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
                Stepper(value: $settings.cooldownSeconds, in: 5...600, step: 1) {
                    Text("Кулдаун: \(Int(settings.cooldownSeconds)) с")
                }
                Stepper(value: $settings.maxInterruptionsPerHour, in: 1...240) {
                    Text("Макс. вмешательств в час: \(settings.maxInterruptionsPerHour)")
                }
                Stepper(value: $settings.distractionSecondsBeforeNudge, in: 8...600, step: 1) {
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

            Section("Нейросеть") {
                Picker("Провайдер", selection: $settings.llmBackend) {
                    ForEach(GremlinLLMBackend.allCases, id: \.self) { b in
                        Text(b.settingsLabel).tag(b)
                    }
                }
                Toggle("Использовать LLM для фраз", isOn: $settings.useLLMForLines)

                if settings.llmBackend == .ollama {
                    TextField("Базовый URL Ollama", text: $settings.ollamaBaseURL)
                    TextField("Модель (текст)", text: $settings.ollamaModel)
                } else if settings.llmBackend == .openAICompatible {
                    TextField("Базовый URL (с /v1)", text: $settings.cloudAPIBaseURL)
                    TextField("Модель (желательно vision, если шлём JPEG)", text: $settings.cloudChatModel)
                    SecureField("API-ключ (не сохраняется в JSON)", text: $openAIKeyDraft)
                    Button("Сохранить ключ OpenAI / совместимого API") {
                        SecureLLMAPIKey.save(openAIKeyDraft, slot: .openAICompatible)
                        openAIKeyDraft = ""
                    }
                    Text(openAICompatibleKeyStatus)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    TextField("Модель Claude", text: $settings.cloudChatModel)
                    SecureField("API-ключ Anthropic", text: $anthropicKeyDraft)
                    Button("Сохранить ключ Anthropic") {
                        SecureLLMAPIKey.save(anthropicKeyDraft, slot: .anthropic)
                        anthropicKeyDraft = ""
                    }
                    Text(anthropicKeyStatus)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Stepper(value: $settings.llmMinIntervalSeconds, in: 3...900, step: 1) {
                    Text("Мин. интервал LLM: \(Int(settings.llmMinIntervalSeconds)) с")
                }
                Text(settings.gremlinLLMDiagnosticLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Проверить соединение") {
                    Task { await settings.runGremlinLLMSmokeTest() }
                }
                Text(
                    "С **картинкой** сейчас один HTTP-запрос: в одном сообщении и текст, и JPEG (multimodal). Отдельный режим «два запроса» (сначала описание экрана, потом реплика) в приложении не включён."
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(
                    "Классификация Smart Mode по-прежнему идёт в **локальную** Ollama (`Vision-модель` ниже), независимо от провайдера реплик."
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Пока не прошёл «Мин. интервал LLM», реплика **не показывается** (никаких заплаток шаблонами). При Ollama чаще всего сбой — не запущен `ollama serve`, нет модели или неверное имя; в облаке — URL, модель и ключ в связке ключей.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Отладка: логировать пайплайн LLM в Console", isOn: $settings.gremlinPipelineDebugLogging)
                Text("Console.app → фильтр по bundle id приложения и `category:llm` — размер JPEG, URL-hint, фрагмент user-промпта.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .onChange(of: settings.smartModeEnabled) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            refreshPermissionSnapshots()
                        }
                    }
                Stepper(value: $settings.smartSamplingIntervalSeconds, in: 5...240, step: 1) {
                    Text("Интервал семплинга: \(Int(settings.smartSamplingIntervalSeconds)) с")
                }
                TextField("Vision-модель Ollama", text: $settings.smartVisionModel)
                Toggle("Сохранять последний кадр в Application Support (отладка)", isOn: $settings.smartDebugSaveFrames)
                    .disabled(!settings.smartVisionConsent)
                Button("Открыть настройки записи экрана") {
                    _ = PermissionGate.requestScreenCaptureAccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        refreshPermissionSnapshots()
                    }
                }
                Button("Настройки → Запись экрана") {
                    PermissionGate.openPrivacyPane(anchor: "ScreenCapture")
                }
                Text("Нужна vision-модель (`ollama pull llava` и т.п.). Интервал семплинга обновляет классификацию экрана для движка; при вмешательстве гоблин всё равно делает **свежий** кадр окна в LLM. Реплики до ~12 слов; кадры по умолчанию не пишутся на диск.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Проверка") {
                Button("Показать тестовое сообщение") {
                    Task { await CompanionSession.playTestMessage() }
                }
                Text("Сообщение и гремлин появляются у указателя мыши на экране, не внутри этого окна. Подведи курсор туда, где хочешь увидеть оверлей.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Приватность и доступы") {
                LabeledContent("Accessibility") {
                    Text(axGrantedSnapshot ? "Включено" : "Нужно для заголовка окна")
                        .foregroundStyle(axGrantedSnapshot ? .green : .orange)
                }
                LabeledContent("Мониторинг ввода") {
                    Text(
                        scrollMonitorActiveSnapshot
                            ? "Скролл детектируется"
                            : "Нужен для doomscroll в браузере (глобальный скролл)"
                    )
                    .foregroundStyle(scrollMonitorActiveSnapshot ? .green : .orange)
                }
                LabeledContent("Запись экрана") {
                    Text(
                        screenGrantedSnapshot
                            ? "Разрешено"
                            : "Только для Smart Mode; базовый режим в браузере работает без этого"
                    )
                    .foregroundStyle(screenGrantedSnapshot ? .green : .secondary)
                }
                Button("Открыть: Accessibility") {
                    PermissionGate.openPrivacyPane(anchor: "Accessibility")
                }
                Button("Открыть: Мониторинг ввода") {
                    PermissionGate.openInputMonitoringPane()
                }
                Button("Открыть: Запись экрана") {
                    PermissionGate.openPrivacyPane(anchor: "ScreenCapture")
                }
                Button("Обновить статус") {
                    refreshPermissionSnapshots()
                }
                Text(
                    "Оранжевая «Запись экрана» не ломает базовый режим. Если в браузере «тишина», чаще всего не включён мониторинг ввода (скролл) или заголовок вкладки без маркеров отвлечения — тогда жди порог секунд «нейтрального» браузера в настройках. Статус обновляется при открытии окна и возврате в приложение; при смене прав — «Обновить статус» или перезапуск."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 640)
        .onAppear { refreshPermissionSnapshots() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let now = Date()
            guard now.timeIntervalSince(lastActivePermissionRefresh) > 1 else { return }
            lastActivePermissionRefresh = now
            refreshPermissionSnapshots()
        }
    }

    private var openAICompatibleKeyStatus: String {
        let has = (SecureLLMAPIKey.read(slot: .openAICompatible)?.isEmpty == false)
        return has ? "Ключ в связке ключей задан." : "Ключ в связке ключей отсутствует."
    }

    private var anthropicKeyStatus: String {
        let has = (SecureLLMAPIKey.read(slot: .anthropic)?.isEmpty == false)
        return has ? "Ключ в связке ключей задан." : "Ключ в связке ключей отсутствует."
    }

    private func refreshPermissionSnapshots() {
        axGrantedSnapshot = PermissionGate.accessibilityTrusted
        screenGrantedSnapshot = PermissionGate.screenRecordingPreflightGranted
        scrollMonitorActiveSnapshot = CompanionSession.focusEngine?.isGlobalScrollMonitorActive ?? false
        if !scrollMonitorActiveSnapshot, SettingsStore.shared.agentEnabled {
            CompanionSession.focusEngine?.restartScrollMonitorIfNeeded()
            scrollMonitorActiveSnapshot = CompanionSession.focusEngine?.isGlobalScrollMonitorActive ?? false
        }
    }
}
