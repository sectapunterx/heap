.pragma library

// Starter content for the Docs view, in the language the profile starts in.
//
// It used to be hardcoded in DocsView.qml in English only, so a Russian
// profile opened on a catalogue of English descriptions. It is seeded once,
// on a profile's first visit, and belongs to the user from then on — which is
// why it is chosen by language at that moment and never re-translated.
//
// `accents` are the four event-type colours from Theme, which a .pragma
// library cannot read itself.

function sections(lang, accents) {
    return lang === "ru" ? [
    {
        "id": "web-standards",
        "title": "Веб- и API-стандарты",
        "subtitle": "Внешние — HTTP, HTML, ECMAScript, доступность, безопасность",
        "accent": accents[0],
        "customFields": [],
        "items": [
            {
                "ref": "RFC 9110",
                "title": "Семантика HTTP",
                "desc": "Основа HTTP — методы, коды ответа, заголовки, условные и диапазонные запросы, кеширование.",
                "url": "https://www.rfc-editor.org/rfc/rfc9110",
                "source": "IETF",
                "version": "2022",
                "updated": ""
            },
            {
                "ref": "RFC 8259",
                "title": "Формат обмена данными JSON",
                "desc": "Грамматика JSON — объекты, массивы, числа, экранирование строк, совместимость.",
                "url": "https://www.rfc-editor.org/rfc/rfc8259",
                "source": "IETF",
                "version": "2017",
                "updated": ""
            },
            {
                "ref": "RFC 6749",
                "title": "Фреймворк авторизации OAuth 2.0",
                "desc": "Типы грантов, токены, обновление, редиректы, вопросы безопасности.",
                "url": "https://www.rfc-editor.org/rfc/rfc6749",
                "source": "IETF",
                "version": "2012",
                "updated": ""
            },
            {
                "ref": "HTML LS",
                "title": "Живой стандарт HTML",
                "desc": "HTML от WHATWG — элементы, семантика, формы, интерфейсы DOM, правила разбора.",
                "url": "https://html.spec.whatwg.org/",
                "source": "WHATWG",
                "version": "living",
                "updated": ""
            },
            {
                "ref": "ECMA-262",
                "title": "Спецификация языка ECMAScript",
                "desc": "Язык JavaScript — грамматика, семантика, встроенные объекты, модули.",
                "url": "https://tc39.es/ecma262/",
                "source": "TC39",
                "version": "ES2024",
                "updated": ""
            },
            {
                "ref": "MDN",
                "title": "MDN Web Docs",
                "desc": "Справочник по HTML, CSS, JS и Web API — документация на каждый день.",
                "url": "https://developer.mozilla.org/",
                "source": "developer.mozilla.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "OpenAPI 3.1",
                "title": "Спецификация OpenAPI",
                "desc": "Описание REST API без привязки к языку — пути, схемы, схемы безопасности.",
                "url": "https://spec.openapis.org/oas/latest.html",
                "source": "OpenAPI",
                "version": "v3.1.0",
                "updated": ""
            },
            {
                "ref": "SemVer",
                "title": "Семантическое версионирование 2.0.0",
                "desc": "Правила MAJOR.MINOR.PATCH — ломающие изменения, пререлизы, метаданные сборки.",
                "url": "https://semver.org/",
                "source": "semver.org",
                "version": "v2.0.0",
                "updated": ""
            },
            {
                "ref": "WCAG 2.2",
                "title": "Руководство по доступности веб-контента",
                "desc": "Воспринимаемость, управляемость, понятность, надёжность — критерии A/AA/AAA.",
                "url": "https://www.w3.org/TR/WCAG22/",
                "source": "W3C",
                "version": "v2.2",
                "updated": ""
            },
            {
                "ref": "OWASP Top 10",
                "title": "OWASP Top 10: риски веб-приложений",
                "desc": "Самые критичные риски безопасности — инъекции, сломанная аутентификация, SSRF и др.",
                "url": "https://owasp.org/www-project-top-ten/",
                "source": "owasp.org",
                "version": "2021",
                "updated": ""
            }
        ]
    },
    {
        "id": "internal",
        "title": "Внутреннее — платформа",
        "subtitle": "Вики, ранбуки, стандарты кода, дежурства",
        "accent": accents[1],
        "customFields": [],
        "items": [
            {
                "ref": "ARCH-001",
                "title": "Обзор архитектуры платформы",
                "desc": "Карта сервисов, жизненный цикл запроса, потоки данных, фоновые задачи, внешние интеграции.",
                "url": "#/wiki/platform/architecture",
                "source": "wiki.internal",
                "version": "",
                "updated": "2 недели назад"
            },
            {
                "ref": "STYLE-01",
                "title": "Стандарт стиля кода и ревью",
                "desc": "Форматирование, именование, обработка ошибок, маленькие PR, тест раньше исправления.",
                "url": "#/wiki/platform/code-style",
                "source": "wiki.internal",
                "version": "",
                "updated": "месяц назад"
            },
            {
                "ref": "BUILD-101",
                "title": "Руководство по сборке и CI",
                "desc": "Локальная настройка, пайплайн CI, кеширование, превью-окружения, автоматизация релизов.",
                "url": "#/wiki/platform/build",
                "source": "wiki.internal",
                "version": "",
                "updated": "3 дня назад"
            },
            {
                "ref": "RUN-001",
                "title": "Ранбук · откат деплоя",
                "desc": "Как откатить неудачный релиз — фича-флаги, blue/green, совместимость БД.",
                "url": "#/runbooks/rollback",
                "source": "runbook",
                "version": "",
                "updated": "неделю назад"
            },
            {
                "ref": "RUN-007",
                "title": "Ранбук · миграция базы данных",
                "desc": "Миграции expand/contract, бэкфиллы, изменение схемы без простоя.",
                "url": "#/runbooks/db-migration",
                "source": "runbook",
                "version": "",
                "updated": "5 дней назад"
            },
            {
                "ref": "RUN-012",
                "title": "Ранбук · разбор всплеска задержек",
                "desc": "Какие дашборды смотреть, журнал медленных запросов, насыщение пулов потоков, промахи кеша.",
                "url": "#/runbooks/latency-spike",
                "source": "runbook",
                "version": "",
                "updated": "вчера"
            },
            {
                "ref": "OPS-CALL",
                "title": "Дежурства и эскалация",
                "desc": "График дежурств, уровни критичности, матрица решений по влиянию на клиентов.",
                "url": "#/wiki/oncall",
                "source": "wiki.internal",
                "version": "",
                "updated": "сегодня"
            },
            {
                "ref": "REL-24.06.2",
                "title": "Заметки к релизу · 24.06.2",
                "desc": "Последний срез — исправление оформления заказа, ускорение переиндексации поиска, настройка лимитов API.",
                "url": "#/releases/24.06.2",
                "source": "release",
                "version": "",
                "updated": "сегодня"
            },
            {
                "ref": "TPL-PR",
                "title": "Шаблон PR и чек-лист ревью",
                "desc": "Что нужно в PR: описание, скриншоты, заметки о производительности, тесты, раскатка и риски.",
                "url": "#/wiki/pr-template",
                "source": "wiki.internal",
                "version": "",
                "updated": "2 месяца назад"
            }
        ]
    },
    {
        "id": "reference",
        "title": "Языки и бэкенд",
        "subtitle": "Языки, базы данных, контейнеры, инфраструктура",
        "accent": accents[2],
        "customFields": [],
        "items": [
            {
                "ref": "TS Handbook",
                "title": "Руководство по TypeScript",
                "desc": "Типы, дженерики, сужение типов, утилитарные типы, модули и конфигурация.",
                "url": "https://www.typescriptlang.org/docs/handbook/intro.html",
                "source": "typescriptlang.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Python Docs",
                "title": "Документация Python",
                "desc": "Справочник по языку и стандартной библиотеке — основной справочник на каждый день.",
                "url": "https://docs.python.org/3/",
                "source": "docs.python.org",
                "version": "3.x",
                "updated": ""
            },
            {
                "ref": "PostgreSQL",
                "title": "Документация PostgreSQL",
                "desc": "Справочник SQL, индексы, EXPLAIN, транзакции, JSONB, репликация.",
                "url": "https://www.postgresql.org/docs/current/",
                "source": "postgresql.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Redis",
                "title": "Документация Redis",
                "desc": "Типы данных, персистентность, pub/sub, истечение ключей, кластер и уведомления keyspace.",
                "url": "https://redis.io/docs/latest/",
                "source": "redis.io",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Docker",
                "title": "Документация Docker",
                "desc": "Справочник Dockerfile, многоэтапные сборки, compose, сеть, тома.",
                "url": "https://docs.docker.com/",
                "source": "docs.docker.com",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Kubernetes",
                "title": "Документация Kubernetes",
                "desc": "Поды, деплойменты, сервисы, config map, пробы, лимиты ресурсов.",
                "url": "https://kubernetes.io/docs/home/",
                "source": "kubernetes.io",
                "version": "",
                "updated": ""
            }
        ]
    },
    {
        "id": "tools",
        "title": "Инструменты и отладка",
        "subtitle": "Профилирование, трассировка, санитайзеры, анализ трафика",
        "accent": accents[3],
        "customFields": [],
        "items": [
            {
                "ref": "git",
                "title": "Справочник Git",
                "desc": "Полный справочник команд — rebase, bisect, reflog, worktree, хуки.",
                "url": "https://git-scm.com/docs",
                "source": "git-scm.com",
                "version": "",
                "updated": ""
            },
            {
                "ref": "curl",
                "title": "Документация curl / libcurl",
                "desc": "Отладка HTTP из командной строки — заголовки, авторизация, TLS, тайминги, повторы.",
                "url": "https://curl.se/docs/",
                "source": "curl.se",
                "version": "",
                "updated": ""
            },
            {
                "ref": "perf",
                "title": "Linux perf",
                "desc": "Сэмплирующий профилировщик, аппаратные счётчики, работа с FlameGraph.",
                "url": "https://perf.wiki.kernel.org/index.php/Main_Page",
                "source": "kernel.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "ASan",
                "title": "AddressSanitizer",
                "desc": "Ошибки памяти во время выполнения — выход за границы, use-after-free. -fsanitize=address.",
                "url": "https://clang.llvm.org/docs/AddressSanitizer.html",
                "source": "clang.llvm",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Wireshark",
                "title": "Wireshark",
                "desc": "Захват и анализ пакетов — HTTP/TLS, gRPC, follow stream, фильтры отображения.",
                "url": "https://www.wireshark.org/docs/",
                "source": "wireshark.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "valgrind",
                "title": "Valgrind",
                "desc": "Memcheck, helgrind, callgrind — медленно, но точно ловит ошибки памяти и гонки.",
                "url": "https://valgrind.org/docs/manual/manual.html",
                "source": "valgrind.org",
                "version": "",
                "updated": ""
            }
        ]
    }
] : [
    {
        "id": "web-standards",
        "title": "Web & API Standards",
        "subtitle": "External — HTTP, HTML, ECMAScript, accessibility, security",
        "accent": accents[0],
        "customFields": [],
        "items": [
            {
                "ref": "RFC 9110",
                "title": "HTTP Semantics",
                "desc": "Core HTTP — methods, status codes, headers, conditional & range requests, caching.",
                "url": "https://www.rfc-editor.org/rfc/rfc9110",
                "source": "IETF",
                "version": "2022",
                "updated": ""
            },
            {
                "ref": "RFC 8259",
                "title": "The JSON Data Interchange Format",
                "desc": "JSON grammar — objects, arrays, numbers, string escaping, interoperability notes.",
                "url": "https://www.rfc-editor.org/rfc/rfc8259",
                "source": "IETF",
                "version": "2017",
                "updated": ""
            },
            {
                "ref": "RFC 6749",
                "title": "OAuth 2.0 Authorization Framework",
                "desc": "Grant types, tokens, refresh flow, redirect handling, security considerations.",
                "url": "https://www.rfc-editor.org/rfc/rfc6749",
                "source": "IETF",
                "version": "2012",
                "updated": ""
            },
            {
                "ref": "HTML LS",
                "title": "HTML Living Standard",
                "desc": "WHATWG HTML — elements, semantics, forms, DOM interfaces, parsing rules.",
                "url": "https://html.spec.whatwg.org/",
                "source": "WHATWG",
                "version": "living",
                "updated": ""
            },
            {
                "ref": "ECMA-262",
                "title": "ECMAScript Language Specification",
                "desc": "The JavaScript language — grammar, semantics, built-ins, modules.",
                "url": "https://tc39.es/ecma262/",
                "source": "TC39",
                "version": "ES2024",
                "updated": ""
            },
            {
                "ref": "MDN",
                "title": "MDN Web Docs",
                "desc": "Reference for HTML, CSS, JS and Web APIs — the daily-driver docs.",
                "url": "https://developer.mozilla.org/",
                "source": "developer.mozilla.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "OpenAPI 3.1",
                "title": "OpenAPI Specification",
                "desc": "Language-agnostic REST API description — paths, schemas, security schemes.",
                "url": "https://spec.openapis.org/oas/latest.html",
                "source": "OpenAPI",
                "version": "v3.1.0",
                "updated": ""
            },
            {
                "ref": "SemVer",
                "title": "Semantic Versioning 2.0.0",
                "desc": "MAJOR.MINOR.PATCH rules — breaking changes, pre-release & build metadata.",
                "url": "https://semver.org/",
                "source": "semver.org",
                "version": "v2.0.0",
                "updated": ""
            },
            {
                "ref": "WCAG 2.2",
                "title": "Web Content Accessibility Guidelines",
                "desc": "Perceivable / operable / understandable / robust — A/AA/AAA success criteria.",
                "url": "https://www.w3.org/TR/WCAG22/",
                "source": "W3C",
                "version": "v2.2",
                "updated": ""
            },
            {
                "ref": "OWASP Top 10",
                "title": "OWASP Top 10 Web Risks",
                "desc": "Most critical web app security risks — injection, broken auth, SSRF, etc.",
                "url": "https://owasp.org/www-project-top-ten/",
                "source": "owasp.org",
                "version": "2021",
                "updated": ""
            }
        ]
    },
    {
        "id": "internal",
        "title": "Internal — Platform",
        "subtitle": "Wiki, runbooks, coding standards, on-call",
        "accent": accents[1],
        "customFields": [],
        "items": [
            {
                "ref": "ARCH-001",
                "title": "Platform Architecture Overview",
                "desc": "Service map, request lifecycle, data flow, async jobs, third-party integrations.",
                "url": "#/wiki/platform/architecture",
                "source": "wiki.internal",
                "version": "",
                "updated": "2 weeks ago"
            },
            {
                "ref": "STYLE-01",
                "title": "Code Style & Review Standard",
                "desc": "Formatting, naming, error handling, small PRs, test-first for bug fixes.",
                "url": "#/wiki/platform/code-style",
                "source": "wiki.internal",
                "version": "",
                "updated": "1 month ago"
            },
            {
                "ref": "BUILD-101",
                "title": "Build & CI Guide",
                "desc": "Local setup, CI pipeline, caching, preview envs, release automation.",
                "url": "#/wiki/platform/build",
                "source": "wiki.internal",
                "version": "",
                "updated": "3 days ago"
            },
            {
                "ref": "RUN-001",
                "title": "Runbook · Deploy Rollback",
                "desc": "How to roll back a bad release — feature flags, blue/green, DB compatibility.",
                "url": "#/runbooks/rollback",
                "source": "runbook",
                "version": "",
                "updated": "1 week ago"
            },
            {
                "ref": "RUN-007",
                "title": "Runbook · Database Migration",
                "desc": "Expand/contract migrations, backfills, zero-downtime schema changes.",
                "url": "#/runbooks/db-migration",
                "source": "runbook",
                "version": "",
                "updated": "5 days ago"
            },
            {
                "ref": "RUN-012",
                "title": "Runbook · Latency Spike Triage",
                "desc": "Dashboards to check, slow-query log, thread pool saturation, cache misses.",
                "url": "#/runbooks/latency-spike",
                "source": "runbook",
                "version": "",
                "updated": "yesterday"
            },
            {
                "ref": "OPS-CALL",
                "title": "On-call Rotation & Escalation",
                "desc": "Pager schedule, severity levels, customer-impact decision matrix.",
                "url": "#/wiki/oncall",
                "source": "wiki.internal",
                "version": "",
                "updated": "today"
            },
            {
                "ref": "REL-24.06.2",
                "title": "Release Notes · 24.06.2",
                "desc": "Latest cut — checkout bug fix, search reindex speedup, API rate-limit tuning.",
                "url": "#/releases/24.06.2",
                "source": "release",
                "version": "",
                "updated": "today"
            },
            {
                "ref": "TPL-PR",
                "title": "PR Template & Review Checklist",
                "desc": "What a PR needs: summary, screenshots, perf notes, tests, rollout & risks.",
                "url": "#/wiki/pr-template",
                "source": "wiki.internal",
                "version": "",
                "updated": "2 months ago"
            }
        ]
    },
    {
        "id": "reference",
        "title": "Language & Backend Reference",
        "subtitle": "Languages, databases, containers, infra",
        "accent": accents[2],
        "customFields": [],
        "items": [
            {
                "ref": "TS Handbook",
                "title": "TypeScript Handbook",
                "desc": "Types, generics, narrowing, utility types, module & config reference.",
                "url": "https://www.typescriptlang.org/docs/handbook/intro.html",
                "source": "typescriptlang.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Python Docs",
                "title": "Python Documentation",
                "desc": "Language reference and standard library — the canonical daily reference.",
                "url": "https://docs.python.org/3/",
                "source": "docs.python.org",
                "version": "3.x",
                "updated": ""
            },
            {
                "ref": "PostgreSQL",
                "title": "PostgreSQL Documentation",
                "desc": "SQL reference, indexing, EXPLAIN, transactions, JSONB, replication.",
                "url": "https://www.postgresql.org/docs/current/",
                "source": "postgresql.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Redis",
                "title": "Redis Documentation",
                "desc": "Data types, persistence, pub/sub, expiration, cluster & keyspace notifications.",
                "url": "https://redis.io/docs/latest/",
                "source": "redis.io",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Docker",
                "title": "Docker Documentation",
                "desc": "Dockerfile reference, multi-stage builds, compose, networking, volumes.",
                "url": "https://docs.docker.com/",
                "source": "docs.docker.com",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Kubernetes",
                "title": "Kubernetes Documentation",
                "desc": "Pods, deployments, services, config maps, probes, resource limits.",
                "url": "https://kubernetes.io/docs/home/",
                "source": "kubernetes.io",
                "version": "",
                "updated": ""
            }
        ]
    },
    {
        "id": "tools",
        "title": "Tools & Debug",
        "subtitle": "Profiling, tracing, sanitizers, packet analysis",
        "accent": accents[3],
        "customFields": [],
        "items": [
            {
                "ref": "git",
                "title": "Git Reference Manual",
                "desc": "Full command reference — rebase, bisect, reflog, worktrees, hooks.",
                "url": "https://git-scm.com/docs",
                "source": "git-scm.com",
                "version": "",
                "updated": ""
            },
            {
                "ref": "curl",
                "title": "curl / libcurl Docs",
                "desc": "HTTP debugging from the shell — headers, auth, TLS, timing, retries.",
                "url": "https://curl.se/docs/",
                "source": "curl.se",
                "version": "",
                "updated": ""
            },
            {
                "ref": "perf",
                "title": "Linux perf",
                "desc": "Sampling profiler, hardware counters, FlameGraph workflow.",
                "url": "https://perf.wiki.kernel.org/index.php/Main_Page",
                "source": "kernel.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "ASan",
                "title": "AddressSanitizer",
                "desc": "Runtime memory bugs — out-of-bounds, use-after-free. -fsanitize=address.",
                "url": "https://clang.llvm.org/docs/AddressSanitizer.html",
                "source": "clang.llvm",
                "version": "",
                "updated": ""
            },
            {
                "ref": "Wireshark",
                "title": "Wireshark",
                "desc": "Packet capture & analysis — HTTP/TLS, gRPC, follow-stream, display filters.",
                "url": "https://www.wireshark.org/docs/",
                "source": "wireshark.org",
                "version": "",
                "updated": ""
            },
            {
                "ref": "valgrind",
                "title": "Valgrind",
                "desc": "Memcheck, helgrind, callgrind — slow but precise memory & race detection.",
                "url": "https://valgrind.org/docs/manual/manual.html",
                "source": "valgrind.org",
                "version": "",
                "updated": ""
            }
        ]
    }
];
}

function snippets(lang) {
    return lang === "ru" ? [
    {
        "title": "Сборка с санитайзерами",
        "lang": "sh",
        "tags": [
            "build",
            "sanitizers"
        ],
        "code": "# AddressSanitizer\ncmake -B build -DCMAKE_CXX_FLAGS='-fsanitize=address -g'\ncmake --build build\n\n# ThreadSanitizer (data races)\ncmake -B build-tsan -DCMAKE_CXX_FLAGS='-fsanitize=thread -g'\n\n# UBSan + ASan combo\ncmake -B build -DCMAKE_CXX_FLAGS='-fsanitize=address,undefined -g'"
    },
    {
        "title": "GDB · подключиться к работающему процессу",
        "lang": "sh",
        "tags": [
            "debug",
            "gdb"
        ],
        "code": "sudo gdb -p $(pgrep -f my-service)\n(gdb) info threads\n(gdb) thread apply all bt 30\n(gdb) bt full\n(gdb) p *this  # pretty-print"
    },
    {
        "title": "curl · отладка HTTP-эндпоинта",
        "lang": "sh",
        "tags": [
            "network",
            "http"
        ],
        "code": "# Timing + headers for a request\ncurl -sS -D - -o /dev/null -w '\\ntime_total: %{time_total}s\\n' \\\n  https://api.example.com/v1/health\n\n# POST JSON with a bearer token\ncurl -sS -X POST https://api.example.com/v1/items \\\n  -H 'Authorization: Bearer $TOKEN' \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"name\":\"widget\"}'"
    },
    {
        "title": "Коды ответа HTTP (справка)",
        "lang": "cpp",
        "tags": [
            "reference",
            "enum"
        ],
        "code": "enum class HttpStatus : int {\n  Ok           = 200,\n  Created      = 201,\n  NoContent    = 204,\n  BadRequest   = 400,\n  Unauthorized = 401,\n  Forbidden    = 403,\n  NotFound     = 404,\n  Conflict     = 409,\n  TooMany      = 429,\n  ServerError  = 500,\n};\n\nconstexpr auto kRequestTimeout =\n  std::chrono::seconds{10};"
    },
    {
        "title": "Структурированное логирование",
        "lang": "cpp",
        "tags": [
            "logging",
            "observability"
        ],
        "code": "// Prefer structured key/value logs — machine-queryable.\nLOG_INFO(\"request.completed\",\n  {{\"method\", req.method}, {\"path\", req.path},\n   {\"status\", res.status}, {\"ms\", elapsed.count()}});\n\n// Warnings carry enough context to act on.\nLOG_WARN(\"cache.miss\", {{\"key\", key}, {\"shard\", shardId}});"
    }
] : [
    {
        "title": "Build with sanitizers",
        "lang": "sh",
        "tags": [
            "build",
            "sanitizers"
        ],
        "code": "# AddressSanitizer\ncmake -B build -DCMAKE_CXX_FLAGS='-fsanitize=address -g'\ncmake --build build\n\n# ThreadSanitizer (data races)\ncmake -B build-tsan -DCMAKE_CXX_FLAGS='-fsanitize=thread -g'\n\n# UBSan + ASan combo\ncmake -B build -DCMAKE_CXX_FLAGS='-fsanitize=address,undefined -g'"
    },
    {
        "title": "GDB · attach to a running process",
        "lang": "sh",
        "tags": [
            "debug",
            "gdb"
        ],
        "code": "sudo gdb -p $(pgrep -f my-service)\n(gdb) info threads\n(gdb) thread apply all bt 30\n(gdb) bt full\n(gdb) p *this  # pretty-print"
    },
    {
        "title": "curl · debug an HTTP endpoint",
        "lang": "sh",
        "tags": [
            "network",
            "http"
        ],
        "code": "# Timing + headers for a request\ncurl -sS -D - -o /dev/null -w '\\ntime_total: %{time_total}s\\n' \\\n  https://api.example.com/v1/health\n\n# POST JSON with a bearer token\ncurl -sS -X POST https://api.example.com/v1/items \\\n  -H 'Authorization: Bearer $TOKEN' \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"name\":\"widget\"}'"
    },
    {
        "title": "HTTP status codes (reference)",
        "lang": "cpp",
        "tags": [
            "reference",
            "enum"
        ],
        "code": "enum class HttpStatus : int {\n  Ok           = 200,\n  Created      = 201,\n  NoContent    = 204,\n  BadRequest   = 400,\n  Unauthorized = 401,\n  Forbidden    = 403,\n  NotFound     = 404,\n  Conflict     = 409,\n  TooMany      = 429,\n  ServerError  = 500,\n};\n\nconstexpr auto kRequestTimeout =\n  std::chrono::seconds{10};"
    },
    {
        "title": "Structured logging",
        "lang": "cpp",
        "tags": [
            "logging",
            "observability"
        ],
        "code": "// Prefer structured key/value logs — machine-queryable.\nLOG_INFO(\"request.completed\",\n  {{\"method\", req.method}, {\"path\", req.path},\n   {\"status\", res.status}, {\"ms\", elapsed.count()}});\n\n// Warnings carry enough context to act on.\nLOG_WARN(\"cache.miss\", {{\"key\", key}, {\"shard\", shardId}});"
    }
];
}

function contacts(lang) {
    return lang === "ru" ? [
    {
        "name": "Olga T.",
        "role": "Техлид",
        "channel": "#eng-leads",
        "mattermost": "@olga.t",
        "color": "#d97a6c"
    },
    {
        "name": "Andrey S.",
        "role": "Старший бэкендер",
        "channel": "#backend",
        "mattermost": "@andrey.s",
        "color": "#6cc4b8"
    },
    {
        "name": "Hiroshi M.",
        "role": "Фронтенд",
        "channel": "#frontend",
        "mattermost": "@hiroshi.m",
        "color": "#7cc492"
    },
    {
        "name": "Masha K.",
        "role": "Руководитель QA",
        "channel": "#qa",
        "mattermost": "@masha.k",
        "color": "#c87fc7"
    },
    {
        "name": "Victor L.",
        "role": "Архитектор",
        "channel": "#architecture",
        "mattermost": "@victor.l",
        "color": "#7da8d9"
    },
    {
        "name": "Дежурный",
        "role": "График дежурств",
        "channel": "#oncall",
        "mattermost": "page: oncall",
        "color": "#e6624c"
    }
] : [
    {
        "name": "Olga T.",
        "role": "Tech Lead",
        "channel": "#eng-leads",
        "mattermost": "@olga.t",
        "color": "#d97a6c"
    },
    {
        "name": "Andrey S.",
        "role": "Senior Backend",
        "channel": "#backend",
        "mattermost": "@andrey.s",
        "color": "#6cc4b8"
    },
    {
        "name": "Hiroshi M.",
        "role": "Frontend",
        "channel": "#frontend",
        "mattermost": "@hiroshi.m",
        "color": "#7cc492"
    },
    {
        "name": "Masha K.",
        "role": "QA Lead",
        "channel": "#qa",
        "mattermost": "@masha.k",
        "color": "#c87fc7"
    },
    {
        "name": "Victor L.",
        "role": "Architect",
        "channel": "#architecture",
        "mattermost": "@victor.l",
        "color": "#7da8d9"
    },
    {
        "name": "On-call",
        "role": "Pager rotation",
        "channel": "#oncall",
        "mattermost": "page: oncall",
        "color": "#e6624c"
    }
];
}
