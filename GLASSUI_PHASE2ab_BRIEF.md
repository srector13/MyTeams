# GlassUI Phase 2ab — Content surfaces + vibrancy/color semantics (card t_3060c82e)

You are working in git worktree at repo root, branch `wt/t_3060c82e` based on main @ f059de1
(Phase 0/1a/1b/1c/1d/1e all merged — glass chrome, sheets, standard controls, typography+geometry are DONE).

Authoritative spec: `docs/UI_AUDIT_IOS27_GLASSUI.md`. Read §3 finding rows and §4 Phase 2 steps 2a/2b
for the 15 findings you must close:

**2a — content surfaces (findings T-4, T-5, H-5, D-5, X-4):**
- T-4: grouped backgrounds + inset rounded section cards via `Theme.Surface` on the team home sections
  (`HomeSections.swift`, `LeadersViews.swift:64`, `TeamHomeView.swift:92` per the table); remove the
  painted-to-match spacer Color views; use `.contentMargins(.horizontal, 10, for: .scrollContent)` on carousels.
- T-5: remove the 40 pt systemBackground slab at `HomeSections.swift:452-454`; add bottom scroll-edge
  effect (`.scrollEdgeEffectStyle(.soft, for: .bottom)` on the page scroll view). This also closes 1b's
  deferred legibility issue: unselected crests scrolling under the floating glass picker must stay readable.
- H-5: `TabBar.swift:177-180` hero — replace the fixed 500 pt color slab with geometry-sized hero +
  `backgroundExtensionEffect()` so it extends under the floating chrome.
- D-5: `GameDetailView.swift:155-173` venue header — concentric radius (Theme.Radius), bottom-weighted
  LinearGradient scrim; note a `backgroundExtensionEffect()` already exists at :201 — do not double-apply.
- X-4: replace the stray literal radii (the 15s, sheet 10-inside-20, etc.) with `Theme.Radius` tokens.

**2b — vibrancy + color semantics (findings X-3, N-2, G-3, G-4, T-6, T-7, LL-2, A-1, B-2, D-6):**
- X-3: every `Color(uiColor: .systemGray)` foreground (32 uses across 13 files: HomeSections, NewsView,
  LoadingView, RemoteImage, StatRowView, BoxScoreTables, GameDetailView, LeadersViews,
  StatPercentageView, StatView, PlayerView, PlayerDetailView, BioViews) -> `.secondary` (captions
  `.tertiary`). Where a systemGray is a *fill* rather than foreground, pick the nearest semantic surface —
  never glass on scrolling content.
- G-3 + N-2: ink on team colors via the existing `teamInk` helpers in `Theme.swift` (~:131-165) which use
  `TeamColors.contrastRatio`. Apply in `GameView.swift` (washed team-color fills with white text) and
  `NewsView.swift:77-78,:88-89` (`.primary.opacity(0.5)` -> `.secondary`/`.tertiary`).
- T-6: `LeadersViews.swift:25-31,:98-101` — NFL Leaders link -> `.buttonStyle(.glass)` with
  `.tint(team.color)` or Label+chevron trailing accessory; card radius -> `Theme.Radius.inner`.
- T-7 + LL-2: color-independent selection marking — followed standings row (`HomeSections.swift:389-391`)
  and followed players (`LeadersViews.swift:240,:267`): add `star.fill` (hierarchical) or capsule wash that
  strengthens under `colorSchemeContrast == .increased`, plus `.accessibilityAddTraits(.isSelected)`.
- G-4: `GameView.swift:182-208` leading/trailing — arrowtriangle up/down `.fill` symbols,
  `.symbolRenderingMode(.hierarchical)`, `.accessibilityLabel("Leading"/"Trailing")`, one consistent size.
- A-1: `AlertsSettingsView.swift:84` + symbols in `AlertsSettings.swift:81-118` — hierarchical rendering,
  `.foregroundStyle(.red)` (via a tint param on AlertsStatusRow) for bell.slash state.
- B-2: `TeamBrowserView.swift:278-280` — `.symbolRenderingMode(.hierarchical)` +
  `.contentTransition(.symbolEffect(.replace))` on the follow toggle.
- D-6: `BoxScoreTables.swift:202-228` SoccerLineupRow — `.accessibilityElement(children: .combine)` with a
  spoken summary ("2 goals, yellow card, substituted 67′"), arrows hierarchical.

## Hard rules
1. NO glass on lazy scrolling card content (§5.2 / B1). Glass stays on chrome only (Theme.Surface.chrome usage sites already in place).
2. `Theme.swift` is the ONLY place allowed to contain OS-version branching (`#available`). App files call Theme primitives directly.
3. Accessibility identifiers must keep working (`teamPicker.team.*`, `teamBrowser.done`, sheet card ids, etc.). If the view tree changes under a UI-test query in `myTeamsUITests/`, UPDATE the query in the same commit and note it.
4. Type stays on `Theme.Typography` — this card changes fills/colors/structure, NOT fonts. Do not touch font modifiers.
5. iOS 26 APIs used directly (deployment target 26.0): contentMargins(for:), scrollEdgeEffectStyle, backgroundExtensionEffect, symbolEffect are all 26+ — fine. `ConcentricRectangle` is iOS 27-only per the audit's "(verify)" — if you use it, wrap it in a Theme.swift primitive with #available and a radius fallback; do NOT sprinkle #available in views.
6. This host is Linux — no xcodebuild, no tests runnable. You may NOT claim builds pass. Keep changes conservative and syntactically careful; run `swiftc -parse` if a Swift toolchain exists (check `which swiftc`), otherwise skip.

## Workflow
- Work on branch `wt/t_3060c82e` (already checked out). Commit logically: one commit per coherent finding group, messages like `feat(glassui-2a): inset section cards on grouped backgrounds (T-4)` — reference finding ids.
- Do NOT merge to main. Do NOT push — the orchestrator pushes after review.
- When done, delete this BRIEF file (`git rm`) as a final commit so the branch carries only product changes.

## Report format (final message)
List: (a) each of the 15 findings -> closed / deferred (with one-line reason); (b) every file changed;
(c) any UI test queries you adjusted; (d) commit hashes with subjects; (e) risks you could not verify without Xcode.
