# Focus Gremlin

Нативное macOS-приложение: плавающий «гремлин» следует за курсором и локально (правила + опционально Ollama) комментирует отвлечения.

## Сборка и запуск

1. Откройте `FocusGremlin.xcodeproj` в **Xcode 15+** (на машине должен быть выбран полный Xcode: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`).
2. Схема **Focus Gremlin** → Run (`⌘R`).
3. Тесты: `⌘U` или `xcodebuild -scheme FocusGremlin -destination 'platform=macOS' test`.

## Ярлык на рабочем столе

После сборки с фиксированным DerivedData:

```bash
cd FocusGremlin
xcodebuild -scheme FocusGremlin -configuration Debug -derivedDataPath ./build -destination 'platform=macOS' build
./create_desktop_shortcut.sh
```

Или укажите путь к `.app` вручную: `./create_desktop_shortcut.sh /path/to/FocusGremlin.app`

## Smart Mode

1. Установите vision-модель в Ollama, например: `ollama pull llava`.
2. В настройках приложения включите **согласие**, затем **Smart Mode**, задайте **Vision-модель** (по умолчанию `llava`) и интервал семплинга.
3. Выдайте **Запись экрана** для Focus Gremlin в «Системные настройки».
4. Кадр сжимается в JPEG в памяти и отправляется только на `127.0.0.1` (Ollama). Опция «отладка» пишет один файл `debug_last_frame.jpg` в Application Support.

## Ollama

```bash
ollama serve
ollama pull llama3.2
```

В настройках приложения укажите базовый URL (по умолчанию `http://127.0.0.1:11434`) и имя модели. Если Ollama недоступна, используются шаблонные фразы.

## Права (Privacy)

| Право | Зачем | Без него |
|------|--------|----------|
| **Accessibility** | Заголовок активного окна (вкладка браузера и т.д.) | Классификация только по bundle ID + грубые эвристики |
| **Input Monitoring** (иногда в паре с Accessibility) | Глобальный монитор колёсика мыши | Нет детектора «длинного скролла», остаются время/alt-tab |
| **Screen Recording** | Только для будущего Smart Mode | Не нужен для текущего MVP |

Кнопка в onboarding / настройках открывает системные настройки приватности.

## Подпись и распространение

- Для отладки: **Signing & Capabilities** → Team, или оставьте automatic signing с личным Apple ID.
- **Hardened Runtime** включён в проекте; для нотаризации добавьте нужные entitlements (сейчас sandbox **выключен** — так проще для Accessibility/глобальных мониторов).
- Bundle ID по умолчанию: `com.focusgremlin.app` (смените под себя).

## Отладка

- Логи: консоль OSLog, подсистема `Bundle.main.bundleIdentifier`, категории `app`, `focus`, `overlay`, `llm`.
- Оверлей: `NSPanel` с `ignoresMouseEvents = true` — клики проходят сквозь пузырь.
- Если панель не видна: проверьте, что агент включён в настройках и окно не вне всех экранов.

## Перегенерация `project.pbxproj`

При запуске `python3 gen_pbx.py` идентификаторы таргетов меняются — обновите `BlueprintIdentifier` в `xcshareddata/xcschemes/FocusGremlin.xcscheme` или пересоздайте схему в Xcode.
