# Fleet Geeks mobile design system

The Flutter apps use the same design language as the web portals. **`design/tokens.json` is the single source of the brand
tokens**: change a value there first, then mirror it in `web/packages/shared/src/tokens.css` (web) and
`packages/fg_core/lib/src/theme.dart` (mobile). This document describes the mobile side: how the tokens map to Flutter,
the component library in `fg_core`, the screen patterns, right-to-left rules and accessibility.

## 1. Brand

| Decision | Mobile |
|---|---|
| Primary: deep petrol teal (trust, engineering, calm operations) | `ColorScheme.primary`, navigation indicator, selected states, hero headers |
| Accent: orange is the **only action colour** (primary buttons, focus ring, key calls to action) | `FilledButton`, `FloatingActionButton`, focused input border, current step, badges |
| Neutrals 0–950 for text and surfaces | `FgColors.n0 … n950`, `FgTokens.canvas/surface/surface2/border/text/textMuted` |
| Semantic: success, warning, danger, info (+ background tints) | `FgTokens.success/successBg …`, used through `FgTone` |
| Logo mark: wheel with gear teeth, the road leaving it, orange hub and lane | `assets/brand/fleetgeeks-mark.svg`, drawn in code by `FgBrandMark` (same geometry) |

The customer app icon uses the teal tile, the workshop app icon the graphite tile (`#162125`) so both can sit on one phone.

## 2. Tokens → Flutter

| tokens.json | Flutter (`fg_core`) | Notes |
|---|---|---|
| `color.teal.*`, `color.orange.*`, `color.neutral.*` | `FgColors.teal50 … teal900`, `orange50 … orange900`, `n0 … n950` | raw palette |
| `color.light`, `color.dark` | `FgTokens.light`, `FgTokens.dark` (a `ThemeExtension`) | read with `context.fg.<token>`; brightness-aware |
| `color.status` (neutral, info, progress, attention, good, bad) | `FgTone` + `FgTokens.tone(tone)` → `(fg, bg)` | one mapping for every status symbol: `toneOf(symbol)` |
| `color.chart.*` | `FgColors.chartCategorical` (8), `chartSequential`, `chartDiverging` | for future charts (fl_chart or CustomPainter) |
| `font.latin` Inter, `font.arabic` IBM Plex Sans Arabic | `FgFonts.latin` / `FgFonts.arabic` (`packages/fg_core/<family>`), bundled TTF 400/500/600/700 | primary font follows the language, the other is the fallback |
| `font.scale` 12/13/15/17/20/24/30/38 | `TextTheme`: labelSmall 12, bodySmall/labelMedium 13, bodyMedium/labelLarge/titleSmall 15, bodyLarge/titleMedium 17, titleLarge/headlineSmall 20, headlineMedium/displaySmall 24, headlineLarge/displayMedium 30, displayLarge 38 | weights 400/500/600/700, line height 1.2 (titles) / 1.5 (body) |
| `font.numerals` tabular, Western digits | `FgFonts.tabular` (`FontFeature.tabularFigures()`), `fmtNum`, `fmtMoney`, `fmtKm` (always `en` digits) | money, odometers, counts, times, plates |
| `space` 4…64 | `FgSpace.s1 … s16`, `FgSpace.gutter` (16), `FgSpace.touch` (48) | 4 dp grid |
| `radius` sm 6 / md 10 / lg 14 / xl 20 / pill | `FgRadius.sm … pill`, `FgRadius.brSm … brPill` | buttons + inputs md, cards lg, sheets/dialogs xl |
| `shadow` sm / md / lg | `FgShadows.sm/md/lg`, `FgShadows.card(brightness)` | cards are flat with a border; shadows only on floating things |
| `motion` fast 120 / base 200 / slow 320 ms, easeOut, easeInOut | `FgMotion.fast/base/slow`, `FgMotion.easeOut/easeInOut` | shimmer and decorative motion stop when the OS asks for reduced motion |

### Component themes (in `fgTheme(brightness, lang:)`)

- **ColorScheme** set explicitly (not `fromSeed`): primary teal, secondary = action orange, tertiary info, error danger,
  surface containers from the neutrals, `surfaceTint` transparent (no Material tinting).
- **Buttons**: `FilledButton` orange 48 dp high, radius 10, semibold label; `OutlinedButton` teal text on outline;
  `TextButton` teal; FAB orange; `SegmentedButton` selected = teal tint.
- **Cards**: flat, 1 dp border, radius 14, no margin (lists add their own spacing).
- **Inputs**: filled surface, outline border, **floating labels**, 2 dp orange focus ring, danger on error.
- **Chips** pill shaped; **NavigationBar** 68 dp, teal pill indicator, labels always shown; **TabBar** orange indicator.
- **Bottom sheets** radius 20 with drag handle; **dialogs** radius 20; **snack bars** floating, inverse surface.
- **List tiles** 16 dp side padding, muted icons; **app bars** on the canvas colour, no elevation, title 20/600.

## 3. Components (`packages/fg_core/lib/src/widgets/`)

| Component | Use |
|---|---|
| `StatusPill(symbol)` | Any D365 status: icon (`FgIcons.status`) + colour (`toneOf`) + translated label. Never colour alone. |
| `CountPill(n)` | Lane / tab counters. |
| `StatCard`, `StatGrid` | Key figures (2 per row on phones, 4 on tablets), tabular numbers, optional tap. |
| `VehicleCard`, `VehicleArt`, `PlateBadge` | Vehicle with class placeholder illustration (car, SUV, van, pickup, truck, bus, bike, equipment), number-plate badge, status, odometer, next due. |
| `SectionCard`, `FgListCard`, `KeyValueRow`, `IconTile` | Content cards, tappable list rows, label/value lines, tinted icon tiles. |
| `FgTimeline`, `FgTimelineEntry` | Vertical timeline with timestamps, state (done / current / upcoming) and photo strips. |
| `OrderProgress` | Ten-stage service order tracker (Requested → Confirmed → Arrived → Received → Diagnosis → Awaiting approval → In progress → QC → Ready → Released), derived from the status by `orderStageIndex`, with known timestamps and "what happens next". Compact mode = stage bar for list cards. |
| `FgStepperHeader` | Wizard progress (numbered steps, "Step 2 of 5 · Service"); earlier steps tappable. |
| `EmptyState`, `ErrorState`, `FgIllustration` | Line illustrations drawn in code (empty, error, offline, done, search, calendar, vehicle); error has retry and shows the API correlation id; network errors get the offline art. |
| `AsyncBody` | Loading (shimmer skeleton) / error (retry) / data for a Riverpod `AsyncValue`; stays scrollable for pull-to-refresh. |
| `Shimmer`, `SkeletonBox`, `SkeletonCard`, `SkeletonList` | Skeleton loaders without extra packages (ShaderMask + gradient transform). |
| `OfflineBanner`, `OutboxButton`, `OutboxScreen`, `connectivityProvider` | Offline / waiting / refused strip, app-bar badge with the outbox count, outbox review (retry / discard). |
| `SignaturePad`, `SignatureController` | Finger signature; `toPngBytes()` renders the strokes with `PictureRecorder` (no plugin). |
| `PhotoTile`, `PhotoStrip`, `PhotoGallery`, `PhotoViewer`, `BeforeAfterSlider`, `EvidenceImage` | Evidence photos (loaded with the user's token), zoomable viewer, before / after comparison. |
| `FgBigButton`, `FgActionBar`, `FgQuickAction`, `FgMenuTile` | 56–96 dp buttons for gate and technicians, bottom action bars, dashboard quick actions, "More" menus. |
| `HeroHeader`, `FgAvatar`, `FgSectionTitle`, `FgBrandMark` | Teal gradient headers, initials avatar, section headings, the logo mark. |
| `FgRefresh`, `FgHaptics`, `runCommand`, `showError`, `showDone`, `pickLookup` | Pull-to-refresh, haptics vocabulary, command feedback (sent / queued / refused), D365 lookup picker sheet. |
| `FgNotice` | Inline info / attention / danger / success message with icon. |
| `OrderEventsTimeline`, `JobProgressList`, `ChecklistResults` | Maintenance cycle views of a service order from the API (`cycle.dart` providers): D365 events (text / textAr by language, photos when the event has one), jobs with planned start / finish and "working now", checklist results grouped by checklist with delivery items marked and QC outcomes. |
| `MessageThread`, `MessagesScreen` | Two-way order messages: my bubbles on the end side, the other side's on the start side, system messages centred; sending goes through the outbox (queued messages show as "waiting to send"); opening the thread marks messages read; unread counts from `unreadMessagesProvider` badge the Orders tab, order cards and the order app bar. |

Icons: **Lucide** (`lucide_icons_flutter`, regular weight) through `FgIcons` only (`lib/src/fg_icons.dart`): navigation,
features, actions, statuses (`FgIcons.status`), vehicle classes (`FgIcons.vehicleClass`) and timeline events
(`FgIcons.event`). Change the icon set in that one file.

## 4. Patterns

- **Navigation**: bottom `NavigationBar` with 5 tabs; the offline strip sits directly above it. Customer: Home, Vehicles,
  Book, Orders, More. Workshop: Board, Gate (gate / advisor roles), Tasks, Parts (stores), More. Detail screens are pushed
  on top and keep the outbox badge in the app bar and the strip at the bottom.
- **Lists**: pull-to-refresh, skeleton while loading, empty state with an illustration and a next step, error state with
  retry. Cards, not tables.
- **One orange thing per screen**: the main action (Book, Submit, Confirm, Start, Scan arrival). Secondary actions are
  outlined or text buttons.
- **Wizards**: stepper header + content + bottom action bar (Back / Continue → final orange Confirm).
- **Camera first**: evidence (category chips → camera → upload), damage (zone on the car map → record → photo), QR (full
  screen scanner with frame and haptic). The daily inspection is a big OK / Not OK checklist (the inspection API has no photo
  field, so it has no camera step).
- **Commands**: every outbox command shows "sent", "saved on this phone" or the refusal; haptic `success` / `warning`.
- **Workshop ergonomics**: big buttons (72–96 dp) for start / pause / finish and the gate; status as large icon + text.

### Maintenance cycle patterns

- **Booking request**: the wizard ends with "Send request" (POST /bookings/{id}/request with the e-check-in). Confirmed at once →
  QR; otherwise a waiting screen without QR. Booking detail (`/bookings/:id`): waiting notice, the workshop's proposed time
  with Accept (orange) / Decline, the QR once confirmed. The app remembers its booking ids (there is no list endpoint).
- **Workshop network** cards: distance (only when a location is sent – the app has no location permission, so none is sent),
  rating with count, on-time %, next free slot, "Workshop confirms" vs "Instant confirmation" pill.
- **Documents and payments**: PDFs are downloaded with the user's token to the temporary folder and opened with the phone's
  viewer; payment links open in the browser, otherwise the API's message (pay at the counter / on account) is shown.
- **Gate**: after admission the camera opens for the front photo; the arrival identity card compares read and booked plates
  (PlateBadge, confidence) and offers manual verification (plate / VIN / override) when the recognition is not sure.
- **Handover**: the signature sheet (signer name + pad) accepts and signs online (signed PDF); without strokes or offline the
  handover is accepted through the outbox without a signed document. A late handover asks for the delay reason and note.

## 5. Right-to-left (Arabic)

- The whole app follows `Directionality` from the locale; layouts use `Row`, `EdgeInsetsDirectional`,
  `AlignmentDirectional`, `PositionedDirectional`, so they mirror automatically. Only symmetric `EdgeInsets` are used
  without direction.
- Directional icons use Lucide's `…Dir` variants (`FgIcons.chevronForward`, `arrowForward`, `arrowBack`), which mirror.
- Things that must **not** mirror are wrapped in `Directionality(textDirection: ltr)`: number plates, the damage map (zones
  are the vehicle's own left / right), the before / after slider, signatures.
- Arabic uses IBM Plex Sans Arabic with letter-spacing 0; Latin fallback is Inter (and vice versa) for mixed text.
- Numbers, money, plates and codes keep Western digits in both languages (`fmtNum`); dates use the locale's format.

## 6. Accessibility

- Touch targets ≥ 48 dp (`MaterialTapTargetSize.padded`, 48 dp minimum button height, 60 dp menu rows, 72–96 dp workshop
  buttons).
- Contrast: token pairs are checked to WCAG AA (≥ 4.5:1 text) in `tokens.json`; status is never colour only (icon + text).
- Semantics: status pills read "Status: …", stat cards read "label: value", timeline entries announce "current step",
  steppers mark the selected step, the offline strip and gate result are live regions, illustrations are excluded from
  semantics, icon buttons have tooltips.
- Text scales with the system font size (no fixed-height text containers except the 48–96 dp buttons, which grow).
- Reduced motion: the shimmer stops when the OS disables animations.

## 7. Haptics

| Call | When |
|---|---|
| `FgHaptics.tap()` | selection: chip, segment, tab, checklist / inspection answer |
| `FgHaptics.light()` | pull-to-refresh, picker sheet opened, search done |
| `FgHaptics.success()` | command sent or queued, booking confirmed, sign-in, gate admitted / released |
| `FgHaptics.warning()` | refused command, validation error, gate refused |
| `FgHaptics.scan()` | QR read |

## 8. Files

| Path | Content |
|---|---|
| `packages/fg_core/lib/src/theme.dart` | tokens (`FgColors`, `FgSpace`, `FgRadius`, `FgMotion`, `FgShadows`, `FgFonts`, `FgTokens`) and `fgTheme()` |
| `packages/fg_core/lib/src/status.dart` | pure-Dart rules: `toneOf`, `orderStages`, `orderStageIndex`, `promiseDelta`, `vehicleKindOf`, `initialsOf` |
| `packages/fg_core/lib/src/fg_icons.dart` | the icon map |
| `packages/fg_core/lib/src/format.dart` | dates, numbers, money, promise countdown |
| `packages/fg_core/lib/src/widgets/` | component library |
| `packages/fg_core/lib/src/cycle.dart` | maintenance-cycle providers (timeline, progress, checklists, documents, messages, unread) and row helpers |
| `packages/fg_core/fonts/` | Inter, IBM Plex Sans Arabic (+ OFL licence texts) |
| `assets/brand/` | logo / icon / splash SVG sources, `png/` renders, `android/` vector adaptive icons |
| `tools/check_i18n.ps1`, `tools/get_fonts.ps1`, `tools/render_brand.ps1`, `tools/apply_vector_icons.ps1` | checks and asset tooling |
