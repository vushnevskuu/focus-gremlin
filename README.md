# Focus Gremlin

Нативное macOS-приложение: плавающий «гремлин» следует за курсором и локально (правила + опционально Ollama) комментирует отвлечения.

## Лендинг (GitHub Pages)

Статическая страница лежит в каталоге [`docs/`](docs/). Чтобы опубликовать сайт:

1. Репозиторий на GitHub → **Settings** → **Pages**.
2. **Build and deployment** → Source: **Deploy from a branch**.
3. Branch: `main`, folder: **`/docs`**, Save.

Сайт будет доступен по адресу вида `https://<user>.github.io/focus-gremlin/` (после первого деплоя подставьте свой URL в `docs/index.html` в тегах `canonical` и `og:image`, если имя репозитория другое).

## Лендинг (Vercel)

В корне репозитория уже лежит [`vercel.json`](vercel.json): при деплое копируется [`docs/`](docs/) → `dist/`, в `canonical` и Open Graph подставляется `https://$VERCEL_URL` (чтобы превью не вели на GitHub Pages).

1. Зайди на [vercel.com](https://vercel.com) → **Add New…** → **Project** → импортируй `vushnevskuu/focus-gremlin` (или свой форк).
2. **Framework Preset:** Other (или оставь авто — сработает `vercel.json`).
3. **Build / Output** подтянутся из `vercel.json`; менять Root Directory **не нужно** (корень репо).
4. **Deploy**. Продакшен-алиас проекта: **https://focus-gremlin.vercel.app** (каждый пуш в `main` пересоберёт сайт, если включён Git integration).

При своём домене в Vercel при желании обнови ссылки в `docs/index.html` вручную.

Локальная проверка сборки:

```bash
bash scripts/vercel-build.sh && open dist/index.html
```

CLI (если установлен и выполнен `vercel login`): из корня репозитория `npx vercel@latest --prod`.

## Установка Xcode на чистую систему

Полный **Xcode** (не только Command Line Tools) ставится так:

1. Открой страницу в Mac App Store (уже можно вызвать из терминала):
   `open macappstore://apps.apple.com/app/xcode/id497799835`
2. Нажми **Получить / Установить** и дождись окончания загрузки (~10+ ГБ).
3. После установки выполни:
   `scripts/after_xcode_installed.sh`  
   (попросит `sudo` для `xcode-select`, примет лицензию, соберёт и откроет приложение).

**Альтернатива (CLI):** установлены Homebrew-пакеты `xcodes` и `aria2`. В терминале (интерактивно, с Apple ID):
`xcodes install 16.3 --select --experimental-unxip`

## Проект Xcode

Файл `FocusGremlin.xcodeproj` **генерируется [XcodeGen](https://github.com/yonaskolb/XcodeGen)** из `project.yml` (совместимость с Xcode 26+). После правок структуры таргетов выполните:

```bash
brew install xcodegen
xcodegen generate
```

Устаревший `gen_pbx.py` можно не использовать, если работаете через XcodeGen.

## Сборка и запуск

1. Откройте `FocusGremlin.xcodeproj` в **Xcode** (рекомендуется `xcode-select` на `Xcode.app`, см. `scripts/after_xcode_installed.sh`).
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
