# DokoDocs — Nepal Launch Plan: MVP to Grand Scale

**Product:** Open-source, self-hostable document scanner & PDF toolkit (local-first, own-your-data)
**Primary market:** Nepal → South Asia → global open-source community
**Model:** Free forever for individuals; one-time NPR-priced license for organizations (self-hosted admin/org features)

---

## Part A — Review Verdict on the Master Prompt

**What's strong and should not change:**
1. Strict phase gates (build → test → document → approve) prevent the classic scope-creep death.
2. Local-first + self-hostable is a genuine differentiator against CamScanner/Adobe Scan, and it maps perfectly onto Nepal's realities: expensive/unstable data, institutional distrust of foreign clouds, and Nepal Rastra Bank / government preferences for locally hosted data.
3. One-time corporate license (no subscription) fits Nepali SME purchasing behavior — subscriptions in USD are a hard sell; one-time NPR invoices are how local software actually gets bought.
4. Flutter + Riverpod + drift is the right stack for a small team shipping to both platforms.

**What must change for Nepal:**
1. **Android-first, iOS-fast-follow.** ~95% of Nepali smartphones are Android, mostly budget devices. Phase 1 release target = Google Play (and direct APK). iOS ships 4–6 weeks later.
2. **Pull Nepali/Devanagari OCR forward.** In the original plan OCR is Phase 4. In Nepal, "scan my citizenship / Lalpurja / SEE certificate and search it in Nepali" IS the killer feature no global competitor does well. Move a basic on-device Nepali+English OCR into Phase 2.5 (right after MVP stabilizes), keep advanced AI in Phase 4.
3. **Payments:** integrate eSewa, Khalti, and FonePay/ConnectIPS for corporate license sales via a simple license-key web portal — do not depend on Google Play billing or Stripe.
4. **Low-end device budget:** MVP must run smoothly on 2–3 GB RAM Android devices; aggressive image compression defaults; APK size target under 40 MB.
5. **Nepali UI from day one**, not Phase 4. Flutter i18n scaffold already exists in Phase 0 — ship en + ne strings in v1.0.

---

## Part B — Step-Wise MVP Plan (Weeks 1–12)

### Step 1 (Weeks 1–2): Foundation — "Phase 0"
- Flutter scaffold, feature-based folders, Riverpod, drift schema (Section 3 of master prompt), CI (lint + test on push), `docs/ARCHITECTURE.md`.
- i18n scaffold with `en` and `ne` locale files from the first commit.
- **Gate:** app builds to empty home screen on Android emulator + iOS simulator.

### Step 2 (Weeks 3–6): Core Scanning MVP — "Phase 1a"
- Camera capture with auto edge detection + manual crop/perspective correction.
- Multi-page session (reorder, retake, delete), filters (Original/Grayscale/B&W/brightness-contrast).
- Local save with thumbnails, home grid/list, folders, filename search.
- Combine to PDF, export PDF/images, native share sheet, system print.
- Guest mode fully functional (no account required — critical for trust positioning).
- **Gate:** full scan → crop → filter → save → PDF → share flow on a real budget Android device (test on something like a 3 GB RAM phone), unit tests on image/PDF utilities, widget test on scan-to-save.

### Step 3 (Weeks 7–8): Release Hardening — "Phase 1b"
- Google Sign-In (Apple Sign-In lands with the iOS build).
- Settings: defaults, theme, language toggle (English/नेपाली), storage = Local only.
- Nepali UI strings complete; crash reporting (self-hosted Sentry to stay on-brand).
- Play Store compliance: data-safety form (easy — you collect nothing by default), permission strings, privacy policy page.
- **Gate:** signed release build, closed beta on Play Console.

### Step 4 (Weeks 9–10): Closed Beta in Nepal
- 100–200 testers: Pulchowk/KU/TU students, 2–3 law offices, 1–2 cooperatives (SACCOs), a school admin office, freelancers.
- Recruit via Nepali tech communities and campus clubs; feedback via a simple Google Form + Discord/Telegram group.
- Fix top-10 issues; measure: crash-free rate > 99%, scan-to-PDF success rate, time-to-first-scan.

### Step 5 (Weeks 11–12): Public v1.0 Launch (MVP live)
- Google Play public release + direct APK download from website (many Nepali users sideload).
- Launch assets: landing page (English + Nepali), demo video showing citizenship-card scan → PDF → share in under 30 seconds.
- Media push: Nepali tech media (TechPana, Gadgetbyte Nepal, ICT Frame), Reddit r/Nepal, Hamro Patro-style community groups, LinkedIn Nepal tech circles.
- Position line: **"तपाईंको कागजात, तपाईंकै फोनमा"** — your documents stay on your device; no foreign server ever sees them (a direct hit against CamScanner's data-practice reputation).

**MVP success criteria (Month 3):** 10,000 installs, 30% D7 retention, 99%+ crash-free, 500+ GitHub stars, at least 3 organizations asking about the corporate tier.

---

## Part C — Full-Phase Grand-Scale Roadmap (Months 3–18)

### Phase 2 (Months 3–5): Sync + Self-Hosting — "own your server"
- Reference backend (Node/NestJS or Go, PostgreSQL, Docker one-command deploy).
- Connectors: custom API, WebDAV, FTP/SFTP, Google Drive, OneDrive, Dropbox.
- LAN PC sync over WiFi (mDNS discovery + manual IP) — huge for offices with unreliable internet: sync to the office PC, no cloud needed.
- Email/password + phone-OTP auth (SMS via Sparrow SMS or similar Nepali gateway behind the pluggable SMS interface).
- iOS App Store release lands here.
- **Nepal angle:** publish a Nepali-language self-hosting guide; partner with a local host (e.g., a Nepali datacenter/VPS provider) for a "deploy DokoDocs server in Nepal in 10 minutes" tutorial. Data-residency-in-Nepal becomes a sales weapon for banks/co-ops/government.

### Phase 2.5 (Months 5–6): Nepali OCR — pulled forward
- On-device OCR: English + Nepali + Hindi. Evaluate ML Kit vs Tesseract for Devanagari accuracy; document the tradeoff; consider a backend OCR option (self-hosted) where on-device accuracy is weak.
- Searchable PDFs + search-by-content in Nepali.
- **This is the moment DokoDocs stops being "another scanner" in Nepal.** Market it hard: "Search inside your Nepali documents."

### Phase 3 (Months 6–9): Full PDF Suite + Security
- Annotation suite, signatures/stamps, watermark, merge/split, page ops.
- Security: app lock, biometrics, secure folder, password-protected PDFs, encrypted secure-folder storage.
- Smart folders, tags, favorites, trash, color labels; secure/expiring/QR/LAN share links; QR scan/generate; full printer support.
- Extra format import/export (DOCX/XLSX/HEIC/TIFF/WEBP...).
- **Nepal angle:** template packs — pre-set naming/tag templates for citizenship, passport, PAN, VAT bill, Lalpurja, academic certificates; "Tax season pack" for VAT-registered SMEs.

### Phase 4 (Months 9–12): AI Layer
- OCR accuracy improvements, handwriting (expectation-managed), background/shadow removal, auto-everything scanning pipeline.
- Translation (ne↔en) of scanned text — extremely useful for visa/abroad-study document workflows, a massive Nepali use case.
- AI summarize / chat-with-PDF via self-hosted or user-provided LLM key only; explicit per-action consent before any document leaves the device.

### Phase 5 (Months 12–18): Corporate Tier + Grand Scale
- Web admin panel: user/storage/sync/server monitoring, analytics.
- License-key activation; one-time fee purchasable in NPR via eSewa/Khalti/FonePay/ConnectIPS and bank transfer with VAT invoice (what procurement departments actually need).
- Multi-user org accounts; server-side office-format conversion (headless LibreOffice).
- **Scale motions:**
  - **Verticals:** law firms (case files), cooperatives/microfinance (KYC — thousands of SACCOs in Nepal), schools/colleges (records), hospitals/clinics, INGOs (donor-compliance documentation), government offices under the Digital Nepal Framework.
  - **Channel:** partner with 2–3 Nepali IT service companies as deployment/reseller partners (they install the self-hosted backend, you share license revenue).
  - **Regional expansion:** the same Devanagari OCR + self-host story sells in India (Hindi) and to the Nepali diaspora (Gulf, Australia, Japan — remittance-family document sharing).
  - **Open-source flywheel:** good CONTRIBUTING docs, "good first issue" labels, GSoC-style student internships with Nepali universities — turns users into contributors and hires.

---

## Part D — Team, Budget, Metrics, Risks

**Minimum team (MVP):** 1–2 Flutter devs, 1 designer (part-time), you as PM/QA. **Scale team (Phase 2+):** +1 backend dev, +1 community/growth person. Total MVP cost in Nepal-market salaries: realistically NPR 15–25 lakh for the first 6 months including devices, hosting, and store fees.

**North-star metrics:** weekly active scanners; docs scanned/user/week; self-hosted server deployments (GitHub/Docker pulls); corporate licenses sold; OCR search usage (post-2.5).

**Top risks & mitigations:**
1. *Free-scanner competition (Google Drive scan is free):* differentiate on privacy + Nepali OCR + self-hosting; never compete on generic features alone.
2. *Devanagari OCR accuracy disappoints:* set expectations, ship English-first search, invest in a Nepali OCR eval set early (this eval set is itself a community-contribution magnet).
3. *Monetization too slow:* corporate pipeline starts during beta — recruit beta orgs that are also license prospects; offer "founding organization" lifetime pricing.
4. *Syncfusion licensing:* verify community-license eligibility before Phase 3, or budget the swap to pure open-source PDF libs to keep the AGPL story clean.
5. *One-person bus factor:* docs-as-you-go discipline from the master prompt is your insurance — enforce it.

**Decision points:** after MVP (Month 3) go/no-go on backend investment based on retention; after Phase 2.5 (Month 6) decide India expansion based on OCR quality; after first 10 corporate licenses decide whether to raise/bootstrap.
