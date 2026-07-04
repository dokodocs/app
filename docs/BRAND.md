# DokoDocs — Brand Guidelines & Asset Generation Prompts

This is the single source of truth for how DokoDocs looks and feels, plus
copy-paste generation prompts for every asset you'll create manually
(Midjourney / DALL·E / Ideogram / Figma / a designer). Asset slots already
exist under `assets/` and are wired into `pubspec.yaml`.

---

## 1. Brand essence

**What DokoDocs is:** an open-source, local-first document scanner for Nepal
first, the world second. It scans, organizes, and syncs documents to a
destination *you* own.

**The name:** *Doko* (डोको) is the traditional Nepali woven bamboo basket
carried on the back — you gather what's yours and carry it yourself. That is
the whole brand in one image: **you carry your own documents; nobody else
holds them.** This is our signature motif.

### Brand personality
| Trait | Means in design |
|---|---|
| **Trustworthy** | Calm, uncluttered, nothing shouting. Privacy is felt, not advertised. |
| **Grounded / local** | Rooted in Nepali craft (doko weave, earthy teal), not generic Silicon-Valley SaaS. |
| **Capable, not flashy** | Fast, light, works offline on a 2GB phone. Confidence through restraint. |
| **Honest / open** | Open-source values → transparent, plain, no dark patterns. |
| **Quietly warm** | Friendly but not childish. A helpful neighbor, not a mascot. |

### Tone of voice
- Plain, short, reassuring. "Your documents stay on your phone." not
  "Leverage enterprise-grade local persistence."
- Bilingual by default (English + Nepali/Devanagari). Nepali is first-class,
  never an afterthought.
- Never fearmonger about privacy — state it calmly as the default.

### App feeling (the one-line brief for any illustrator)
> *Calm, earthy, trustworthy, and light — a quiet tool made by people who
> respect your data and your slow connection. Woven, grounded, human.*

---

## 2. Color system

Seed color drives the Material 3 palette (`lib/core/theme/app_theme.dart`).
Everything else is derived from it — don't hand-pick random accents.

| Role | Hex | Use |
|---|---|---|
| **Primary / Seed** | `#2E7D6B` | Doko Teal — brand core, buttons, app bar, adaptive-icon bg |
| Primary dark | `#1F5A4C` | pressed states, gradients |
| Primary light | `#4E9E8A` | highlights, subtle fills |
| **Accent (warm)** | `#D98F3D` | Bamboo/terracotta — the *one* warm accent (a doko basket color). Use sparingly: highlights, illustration warmth. |
| Neutral ink | `#1E2422` | primary text (near-black, slightly green-warm) |
| Neutral muted | `#6B7671` | secondary text, captions |
| Surface / bg light | `#F7F9F8` | app background (light) |
| Surface dark | `#121615` | app background (dark) |
| Success | `#3E8E5A` | sync ok |
| Warning | `#D98F3D` | (reuse accent) |
| Error | `#C1533F` | earthy red, not pure #F00 |

**Rules**
- Teal + one warm accent + neutrals. That's the whole palette. Resist adding
  colors.
- Illustrations use a **2-color** style: Doko Teal + Bamboo accent on neutral.
- Meet WCAG AA (4.5:1) for text. Test both light and dark.

---

## 3. Typography

Already set in `app_theme.dart` — **calm and low-weight** (nothing above
w500). Headings are quiet emphasis, not shouting.
- Latin: system default (Roboto/SF) — zero asset weight, best perf.
- Devanagari: system default renders Nepali fine; if you want a branded
  Devanagari face later, ship one subset-woff font (watch APK size).
- Keep the existing small type scale. Don't upsize.

---

## 4. Motif & illustration style

- **Signature motif:** the *doko* basket weave — a diagonal bamboo cross-hatch.
  Use it subtly: low-opacity background patterns, empty-state props, the logo.
- **Illustration style:** flat, 2-color line + fill, rounded corners, gentle.
  Think "modern flat with a woven texture," not gradient-heavy 3D.
- **Do:** clean line weights, generous whitespace, earthy palette, humans of
  South-Asian appearance where people appear.
- **Don't:** photographic backgrounds, drop-shadow-heavy skeuomorphism, neon,
  clip-art, generic corporate blue, cartoon mascots.

---

## 5. Global prompt preamble (paste before every image prompt)

> Flat 2-color vector illustration for a mobile app. Palette strictly:
> teal #2E7D6B (primary), warm bamboo #D98F3D (single accent), neutral ink
> #1E2422, off-white #F7F9F8 background. Calm, minimal, trustworthy, earthy.
> Rounded shapes, clean even line weights, generous negative space. Subtle
> woven bamboo-basket (doko) cross-hatch texture as a recurring motif. No
> photorealism, no gradients-heavy 3D, no drop shadows, no text unless
> specified. South-Asian / Nepali context where people or objects appear.

---

## 6. Asset-by-asset generation prompts

### A. Logo — `assets/logo/`
Deliver as **SVG** (vector master), plus PNG exports.

**A1. Logo mark (icon only)** → `assets/logo/mark.svg`
> Design a minimal app logo mark: a stylized *doko* (Nepali woven bamboo
> basket) that also reads as a stacked document / page corner. Formed from a
> few diagonal woven strokes suggesting bamboo weave. Single teal #2E7D6B on
> transparent, geometric, balanced in a square, works at 24px and 1024px.
> Flat, no text, no shadow. Should feel like "carry your own documents."

**A2. Horizontal wordmark** → `assets/logo/wordmark.svg`
> The logo mark to the left of the word "DokoDocs" in a calm, medium-weight
> humanist sans-serif, letter-spacing relaxed. "Doko" slightly emphasized.
> Teal #2E7D6B. Provide on transparent background. Also produce a reversed
> all-white version for dark/colored surfaces.

**A3. Devanagari lockup** → `assets/logo/wordmark_ne.svg`
> The same logo mark paired with "डोकोडक्स" in clean Devanagari, matched
> visual weight to the Latin wordmark. Teal #2E7D6B. Balanced, legible at
> small sizes.

**A4. Monochrome variants** → `assets/logo/mark_mono_dark.svg`, `mark_mono_light.svg`
> Single-color silhouette versions of the mark: one solid ink #1E2422, one
> solid white. Flat, transparent background.

---

### B. Launcher / system icons — `assets/icon/`
You already have `icon_1024.png` and `icon_foreground_1024.png`. Add:

**B1. Adaptive foreground refresh (if redesigning)** → `icon_foreground_1024.png`
> 1024×1024 transparent PNG. The doko/document mark centered inside the safe
> zone (keep all art within the central 66% circle, ~666px). Teal + bamboo
> accent on transparent. Simple enough to read at 48px.

**B2. Android monochrome (themed icon)** → `assets/icon/icon_monochrome_1024.png`
> 1024×1024, single flat white silhouette of the mark on transparent, all
> detail within the central safe zone. Used for Material You themed icons.

**B3. Notification icon** → `assets/icon/notification_24.png` (+ densities)
> Pure white silhouette of the simplified mark on fully transparent
> background, flat, no gradient, optimized to read at 24×24dp. Android
> renders it as a solid white glyph, so silhouette only.

**B4. iOS dark & tinted icon** → `icon_1024_dark.png`, `icon_1024_tinted.png`
> Dark variant: mark on a deep teal #1F5A4C background. Tinted variant:
> grayscale mark on transparent for iOS 18 system tint. Both 1024×1024, no
> alpha where iOS requires.

---

### C. Splash — `assets/splash/`
Native cold-start splash via `flutter_native_splash`. Keep it a **centered
mark on a solid color** — no image background (fastest boot).

**C1. Splash logo** → `assets/splash/splash_logo.png` (512×512 transparent)
> The logo mark, centered, teal #2E7D6B, on transparent. Clean, ~60% of frame.

**C2. Android 12+ splash icon** → `assets/splash/splash_android12.png`
> The mark centered inside a 960×960 transparent canvas, art confined to the
> central 288×288 region per Android 12 splash spec.

**C3. Dark splash logo** → `assets/splash/splash_logo_dark.png`
> Same mark in white/light teal for the dark-mode splash on #121615.

Background color for both: **#2E7D6B (light) / #121615 (dark)** — set in config, not an image.

---

### D. Onboarding & empty-state illustrations — `assets/illustrations/`
All **SVG**, one consistent 2-color style, ~portrait or square. Use the
global preamble (§5) + these scene lines:

**D1. Onboarding 1 — Scan** → `onboard_scan.svg`
> A hand holding a phone scanning a paper document on a table; a bright scan
> frame highlights the page edges. Conveys "scan any document instantly."

**D2. Onboarding 2 — Organize** → `onboard_organize.svg`
> Neat stacks of documents sorting into labeled folders, with the woven doko
> pattern subtly on the folders. Conveys tidy, effortless organization.

**D3. Onboarding 3 — Own your data** → `onboard_own.svg`
> A person carrying a *doko* basket full of documents on their back, walking
> away from a generic cloud toward a small house/personal server they own. A
> broken/dotted line to the corporate cloud, a solid line to their own
> device. Conveys "you own where your documents live." This is the hero image.

**D4. Home empty state** → `empty_home.svg`
> A friendly empty doko basket with one paper peeking out and a soft "+"
> prompt, lots of whitespace. Inviting, not sad. "No documents yet — scan
> your first."

**D5. Search empty** → `empty_search.svg`
> A magnifying glass over an open empty doko basket. Calm, "no results."

**D6. Offline / local-first** → `state_offline.svg`
> A phone with a checkmark and a small "no-cloud-needed" cue, reassuring
> tone. "Works fully offline."

**D7. Sync success** → `state_sync_ok.svg`
> Document moving along a solid line from phone to a user-owned server with a
> teal checkmark.

**D8. Sync error** → `state_sync_error.svg`
> Same setup with a bamboo-accent warning, gentle not alarming. Retry cue.

---

### E. Patterns / backgrounds — `assets/patterns/`
Keep ultra-light. Prefer a small **tileable SVG**, low opacity.

**E1. Doko weave pattern (tile)** → `assets/patterns/weave_tile.svg`
> A seamless, tileable diagonal bamboo-weave (doko) pattern: thin
> interlocking strokes, teal #2E7D6B at ~6–10% opacity on transparent.
> Extremely subtle — meant to sit behind onboarding/auth screens without
> reducing text contrast. Must tile perfectly with no visible seams.

**E2. Auth/onboarding backdrop (optional)** → draw in code
> Prefer a vertical gradient #F7F9F8 → very light teal in a Flutter
> `CustomPainter` (no asset). If you want an image: a large, very faint doko
> weave in one corner only.

---

### F. Store / marketing — `assets/store/` (NOT bundled in APK)

**F1. Google Play feature graphic** → `store/play_feature_1024x500.png`
> 1024×500 banner. Left: "DokoDocs — Scan. Organize. Own your data." in calm
> type. Right: the doko-basket-of-documents hero illustration. Teal +
> bamboo, off-white background, woven texture. Bilingual tagline optional.

**F2. Play hi-res icon** → `store/play_icon_512.png` (512×512, 32-bit PNG).

**F3. App Store icon** → `store/appstore_icon_1024.png` (1024×1024, no alpha).

**F4. Phone screenshots (en + ne)** → `store/screenshots/…`
> Framed device mockups of Home, Scan, PDF export, and Sync/Own-your-data
> screens, each with a short caption in English and Nepali, on an off-white
> #F7F9F8 background with a faint weave corner.

**F5. README / social hero** → `store/hero.png`
> Wide banner reusing the "person carrying doko of documents away from the
> cloud" hero image with the wordmark.

---

## 7. Performance guardrails (do not violate)
- Illustrations & logo ship as **SVG** (or WebP if you skip `flutter_svg`).
  Never full-screen JPG/PNG backgrounds.
- Launcher icon stays **PNG** (tooling requirement); everything else vector.
- Total `assets/` (excluding `store/`) target: **< 2 MB**.
- Backgrounds: solid color / code gradient / tiny tiled SVG only.
- Provide raster UI assets at @1x/@2x/@3x only when SVG isn't possible.
- Keep the APK under the **40 MB** Nepal target.

## 8. Quick reference card
- **Colors:** Teal `#2E7D6B` + Bamboo `#D98F3D` + neutrals. Nothing else.
- **Feeling:** calm, earthy, trustworthy, light, woven, human.
- **Motif:** the doko basket / bamboo weave = "carry your own documents."
- **Voice:** short, plain, bilingual, privacy-as-default (never fearmongering).
- **Type:** low-weight (≤ w500), small, quiet.
