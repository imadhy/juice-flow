# Contributing to JuiceFlow

Thanks for considering it! This project is deliberately lightweight to hack on.

## Dev setup

You only need **Command Line Tools** (`xcode-select --install`) — no Xcode:

```sh
swift build                  # debug build
./scripts/bundle.sh          # release build → build/JuiceFlow.app, ad-hoc signed, launched
./scripts/bundle.sh --no-open
./scripts/build-iconset.sh   # regenerates Resources/AppIcon.icns from code
./scripts/make-dmg.sh        # release .dmg
```

Fast feedback loop while developing:

```sh
.build/debug/JuiceFlow --dump    # battery/SMC/autonomy readings vs pmset & ioreg
.build/debug/JuiceFlow --top 3   # estimation ranking vs `top -o cpu`
.build/debug/JuiceFlow --pm 6    # powermetrics parsing (needs the sudoers rule)
```

## Project map

| Path | What lives there |
|---|---|
| `Sources/JuiceFlow/BatterySnapshot.swift` | IOKit `AppleSmartBattery` reader |
| `Sources/JuiceFlow/SMCPowerReader.swift` | SMC client (live watts: `PPBR`/`PDTR`/`PSTR`) |
| `Sources/JuiceFlow/ProcessSampler.swift` + `ProcessService.swift` | libproc sampling, responsible-PID grouping, EMA smoothing, badges |
| `Sources/JuiceFlow/PowerMetrics/` | `powermetrics` stream, plist parser, sudoers setup |
| `Sources/JuiceFlow/History/` | SQLite store, recording service, Charts view |
| `Sources/JuiceFlow/Intelligence/` | notifications (AlertService), session score |
| `Sources/JuiceFlow/Components/` | gauge, power flow, rows, detail panel, menu bar |
| `Sources/JuiceFlow/Settings/` | Settings window, onboarding |
| `docs/RECETTE.md` | manual acceptance checklist (French) |

## Conventions

- Swift 6 strict concurrency; services are `@MainActor @Observable` classes, readers are pure `enum` namespaces.
- The UI language and code comments are currently **French** — contributions in English are welcome; a proper localization pass is on the roadmap (help wanted!).
- `swift build` must stay **warning-free**.
- Small, focused commits with imperative subjects.

## Testing a change

There is no unit-test suite yet (contributions welcome). The bar for a PR:

1. `swift build` clean.
2. The relevant CLI diagnostic cross-checked (`--dump` vs `pmset -g batt`, `--top` vs `top -o cpu`).
3. For UI changes: a screenshot in the PR, light & dark if relevant.
4. For anything touching measurement or the sudoers mechanism: explain the security reasoning in the PR description.

## Reporting issues

Include: macOS version, chip (`sysctl -n machdep.cpu.brand_string`), whether precision mode is enabled, and the output of `.build/debug/JuiceFlow --dump`.
