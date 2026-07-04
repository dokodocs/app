# DokoDocs — Optimized Claude Code Prompt (Nepal-First Build)

Paste the block below into Claude Code at the root of an empty project directory, with `dokodocs-master-prompt.md` placed in the same directory.

---

```
## Objective
Build DokoDocs — an open-source, local-first, self-hostable document scanner and PDF toolkit in Flutter — strictly phase-by-phase, optimized for a Nepal-first launch. The full product specification is in ./dokodocs-master-prompt.md. Read that entire file before writing any code; it is the authoritative spec. This prompt adds Nepal-specific overrides and your working rules.

## Context
- Empty repository. Nothing exists yet.
- Spec file: ./dokodocs-master-prompt.md (Sections: 1 product, 2 tech stack, 3 data model, 4 screens, 5 phased plan, 6 non-functional, 7 docs, 8 agent instructions).
- Primary market is Nepal: ~95% Android on budget devices (2–3 GB RAM), unstable/expensive connectivity, Nepali (Devanagari) is the primary local language.
- Business model: free core, one-time NPR-priced corporate license on the self-hosted backend (never gate mobile core features).

## Nepal-First Overrides (these MODIFY the master prompt — apply them)
1. Android is the primary release target; iOS must still compile and pass tests each phase, but polish and store submission for iOS trail Android by one phase.
2. i18n from Phase 0 with `en` AND `ne` locale files; every user-facing string goes through localization from the first widget. Ship complete Nepali UI in Phase 1, not Phase 4.
3. Performance budget: smooth on 3 GB RAM Android; release APK ≤ 40 MB (use split ABIs / app bundle); default image compression tuned for low storage; every image operation off the main isolate.
4. Move basic OCR (English + Nepali via on-device engine — evaluate ML Kit vs Tesseract for Devanagari, document the tradeoff in docs/OCR_EVAL.md) to a new Phase 2.5, between Phase 2 and Phase 3. Advanced AI features remain Phase 4.
5. Backend SMS-OTP interface must be pluggable with a Nepali gateway driver stub (e.g., Sparrow-SMS-style REST) alongside a generic provider.
6. Corporate license purchase flow (Phase 5) assumes eSewa/Khalti/FonePay payment callbacks feeding a license-key issuance endpoint — design the LicenseKeys API so payment providers are pluggable; do NOT integrate Stripe as the default.
7. Prefer fully open-source libraries; if syncfusion_flutter_pdf license eligibility is uncertain, propose an open-source alternative before using it.

## Target State (per phase — binary)
- Phase N is done ONLY when: (a) `flutter build apk --release` succeeds and the app runs the phase's features on an Android emulator, (b) iOS builds in the simulator, (c) all phase tests pass via `flutter test`, (d) docs/PHASE_N_SUMMARY.md is written, (e) you have paused and I have explicitly approved continuing.

## Scope
- Work only inside the repository root.
- Do NOT create accounts, cloud resources, Firebase projects, or OAuth clients — instead output a manual-setup checklist (console steps, SHA-1 fingerprint, Info.plist strings, entitlements) in each phase summary for me to perform.
- Do NOT touch signing keys, .env values, or store credentials.

## Constraints
- Latest stable Flutter, Dart null-safety, Riverpod, drift — exactly per spec Section 2; verify each package on pub.dev before adding, replace deprecated ones and record every substitution with a one-line justification in docs/DEPENDENCIES.md.
- Only build the current phase. Do not implement, scaffold, or stub features from future phases beyond what the data model in Section 3 requires.
- Only make changes directly requested by the spec and these overrides. Do not add features, abstractions, or files beyond what was asked.
- Every schema change ships with a drift migration and a note in docs/DATABASE.md.
- Accessibility and permission-rationale requirements from Section 6 apply from Phase 1, not later.

## Acceptance Criteria (Phase 1 release gate — the MVP)
- [ ] Scan → auto edge detect → manual crop → filter → multi-page reorder → save → combine to PDF → share completes on an Android emulator with no crash
- [ ] Guest mode works with zero network access (airplane mode)
- [ ] UI fully switchable English ↔ नेपाली at runtime
- [ ] Unit tests cover image pipeline + PDF utilities; one widget test covers scan-to-save
- [ ] Release APK ≤ 40 MB; docs/PHASE_1_SUMMARY.md + docs/STORE_COMPLIANCE.md written

## Stop Conditions
Stop and ask before:
- Adding any dependency not listed in spec Section 2
- Deleting any file, modifying CI config after Phase 0, or changing the database schema outside a planned migration
- Making any architectural decision the spec leaves open (backend language choice, scanner package choice, OCR engine choice) — present options with a recommendation, wait for my pick
- Starting any new phase

## Progress
After each completed step output: ✅ [what was done] — [files affected]
At each phase end output: build status, test results, manual-setup checklist for me, open decisions, then STOP and wait for approval.

## Session Strategy
Continue across the phase; when context grows large, run /compact focusing on: current phase scope, data model, dependency decisions, and my approvals. Use a subagent for package-research tasks (pub.dev verification, OCR engine comparison) so research output stays out of the main context.

Begin now with: (1) confirm you have read ./dokodocs-master-prompt.md in full, (2) list any spec/override conflicts you detect, (3) then start Phase 0.
```

---

🎯 **Target:** Claude Code (Opus-class agentic session)
💡 **Optimized for:** literal instruction-following with front-loaded context — Nepal overrides, binary phase gates, hard scope locks, stop conditions, and subagent/compact strategy so one long session maximizes context and token efficiency without scope creep.

⚠️ This prompt is for an agentic tool with real system access. Review the scope locks, forbidden actions, and stop conditions before pasting. Confirm file paths, directories, and permissions match the actual project.
