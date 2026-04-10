import Foundation

/// Процедурные шаблоны (не единственные фразы из ТЗ — вариации через плейсхолдеры и случайный выбор).
enum TemplatePhraseBank {
    static func fallbackLine(language: AppLanguage, tone: ToneIntensity, trigger: DistractionTrigger) -> String {
        if language == .ru {
            return ruLine(tone: tone, trigger: trigger)
        }
        return enLine(tone: tone, trigger: trigger)
    }

    /// Короткие «вокальные» вставки, когда LLM включён, но ещё рано по интервалу — не полноценная речь, а кряхтенье/смех.
    static func vocalInterjection(language: AppLanguage, memory: RecentMessageMemory) -> String {
        let pool = language == .ru ? ruVocalPool : enVocalPool
        for _ in 0..<28 {
            guard let c = pool.randomElement() else { break }
            if !memory.containsRecent(c) { return c }
        }
        return pool.randomElement() ?? "…"
    }

    private static let ruVocalPool: [String] = [
        "Хммм…", "Пф!", "Тьфу.", "Хе-хе…", "Ахах, ну да.", "Гррр.", "Эх…", "Тсс.", "М-м-м…", "Ну-ну.",
        "Ого-го.", "Ха!", "Фу.", "…серьёзно?", "Нда уж.", "Угу, конечно.", "Кх-кх…", "Брр.", "Хнык-ирония.",
        "Лол.", "Ага.", "Мда.", "Тск.", "Хррм.", "Вот это да.", "Иии?", "Ну блин.", "Пффф."
    ]

    private static let enVocalPool: [String] = [
        "Hmph.", "Heh.", "Tsk.", "Pfft.", "Ha.", "Haha—no.", "Ugh.", "Mmm…", "Seriously?", "Wow.",
        "Grr.", "Yeah right.", "Huh.", "Ew.", "Riiight.", "Khh…", "Bruh.", "Sigh.", "Oh please.",
        "Lol.", "Mm-hmm.", "Uh-huh.", "Tch.", "Hrm.", "Wow. Just wow.", "Really?", "Pfft—okay.", "Nope."
    ]

    private static func ruLine(tone: ToneIntensity, trigger: DistractionTrigger) -> String {
        switch trigger {
        case .sustained:
            return pick([
                "Ты уже достаточно «исследовал» этот экран. Может, вернёмся к делу?",
                "Это стратегическая пауза или люкс-версия избегания?",
                "Я не спешу. Но дедлайн, похоже, тоже не спешит — и это тревожно.",
                "Слушай, я за тебя рад… но не настолько, чтобы молчать вечно."
            ], tone: tone)
        case .scrollSession:
            return pick([
                "Бро, это ресёрч или ты уже в археологии ленты?",
                "Колёсико мыши горячее. Руки в порядке?",
                "Ты скроллишь так уверенно, будто там внизу спрятан смысл жизни.",
                "Если бы скролл был спортом, ты бы уже взял медаль. Но задача всё ещё ждёт."
            ], tone: tone)
        case .chaoticSwitching:
            return pick([
                "Alt+Tab у тебя как диджейский пульт. Только трек не заканчивается.",
                "Ты прыгаешь между окнами быстрее, чем я успеваю моргнуть.",
                "Это фокус или микс из двадцати вкладок и надежды?",
                "Сейчас был рабочий импульс. Куда ты его дел?"
            ], tone: tone)
        case .boomerang:
            return pick([
                "О, ты вернулся. Я уже начал скучать по этой вкладке.",
                "Назад так быстро? Я даже не успел налить чай с сарказмом.",
                "Это ремикс «ещё пять минут» в исполнении твоего я.",
                "Ты как бумеранг: улетел в работу и снова сюда. Магия."
            ], tone: tone)
        case .smartVision:
            return pick([
                "Мой локальный «взгляд» на экран говорит: это не похоже на работу. Обсудим?",
                "Заголовок окна молчит, а картинка кричит. Может, сменим контекст?",
                "Я не шпион из облака — это твой Mac. Но даже он видит, что тут не дедлайны.",
                "Смарт-режим поймал вайб прокрастинации. Давай честно: это точно задача?"
            ], tone: tone)
        case .pageChange:
            return pick([
                "О, новая страница. Мусор сам себя листать не станет.",
                "Свежая вкладка, старые привычки. Какая трогательная деградация.",
                "Сменил страницу, не курс. Классика.",
                "Новый экран, тот же побег от дела."
            ], tone: tone)
        }
    }

    private static func enLine(tone: ToneIntensity, trigger: DistractionTrigger) -> String {
        switch trigger {
        case .sustained:
            return pick([
                "You’ve been here a while. Research… or ritual procrastination?",
                "I’m not judging. I’m just very interested in this tab.",
                "If focus were a muscle, this screen is a comfy couch.",
                "Your future self is side-eyeing you. I’m just the messenger."
            ], tone: tone)
        case .scrollSession:
            return pick([
                "That scroll wheel is working harder than the task.",
                "Deep dive, or deep drift?",
                "You’re mining the feed like there’s treasure at the bottom.",
                "The algorithm loves you. Your todo list… is patient."
            ], tone: tone)
        case .chaoticSwitching:
            return pick([
                "Your alt-tab game is Olympic. The deliverable is still in the audience.",
                "Blinking between apps won’t merge the PR for you.",
                "This isn’t multitasking. It’s channel surfing with anxiety.",
                "Pick a lane. Any lane. Even the boring one counts."
            ], tone: tone)
        case .boomerang:
            return pick([
                "Back already? That was a speedrun away from productivity.",
                "You bounced out and ricocheted right back. Impressive physics.",
                "Welcome back to your favorite distraction. It missed you too.",
                "Short trip. Big feelings. Still the same tab though."
            ], tone: tone)
        case .smartVision:
            return pick([
                "My on-device peek says this isn’t a work vibe. Wanna pivot?",
                "The window title is shy, but the pixels are loud. Interesting.",
                "Local vision mode spotted classic procrastination energy. No cloud involved.",
                "Smart mode caught the screen looking… extremely not like a deliverable."
            ], tone: tone)
        case .pageChange:
            return pick([
                "New page. Same swamp.",
                "Fresh tab, same avoidance.",
                "Different sludge, same ritual.",
                "New screen, old escape."
            ], tone: tone)
        }
    }

    private static func pick(_ lines: [String], tone: ToneIntensity) -> String {
        switch tone {
        case .gentle:
            return lines.randomElement() ?? lines[0]
        case .snarky, .intervention:
            return lines.shuffled().first ?? lines[0]
        }
    }
}
