# Fleet Geeks mobile apps (Flutter)

Two Android apps that talk only to the **Fleet Geeks API** (never to D365 directly):

| App | Folder | Who | Navigation and screens |
|---|---|---|---|
| Fleet Geeks Workshop | `apps/workshop_app` | Gate, advisors, technicians, QC, stores | Bottom tabs **Board** (stage sections with vehicle cards, key figures, at-risk banners), **Gate** (big scan buttons, result card), **Tasks** (vehicles in the work stages + pickups / deliveries), **Parts**, **More**. Service order in tabs (Jobs, Inspection = health check + damage map, Evidence = camera + gallery with before / after slider, Handover = accept with signature / reject with reason, Timeline). Technician job screen with big start / pause / finish buttons. Gate arrival photo with plate recognition and manual verification. Signed handovers (signed PDF), late-handover reasons, offer handover, delivery checklist, order messages, bookings to confirm (confirm / other time / decline). Outbox. |
| Fleet Geeks | `apps/customer_app` | Customers, drivers, internal fleet managers | Bottom tabs **Home** (greeting, key figures, quick actions, "needs your action", latest orders), **Vehicles** (search, filter, vehicle cards), **Book** (5-step wizard with job type, variant, workshop network and e-check-in → booking request; QR once the workshop confirms), **Orders** (active / completed with stage bar), **More**. Booking detail (waiting / proposed time accept-decline / arrival QR), vehicle 360 with the digital service book (PDF), service order with the 10-stage tracker and "what happens next", D365 timeline, live job progress, checks incl. delivery, documents (PDF), messages, payment, estimate decision, photos; daily inspection, fault report, fuel & incidents, pool vehicles, compliance, outbox. |

Shared code is in `packages/fg_core`: API client, sign-in, **offline outbox**, English / Arabic text (right-to-left), and the
design system – theme from `design/tokens.json`, Lucide icon map, bundled fonts and the widget library. See
[DESIGN.md](DESIGN.md).

## Offline behaviour

Job start / pause / finish, checklist answers, QC results, handover responses, damage points, health check ratings, parts
issue, odometer readings, inspections, fuel, incidents, pool check-out / check-in and fault reports go through the outbox.
With no signal the command is stored on the phone (SQLite) with its Idempotency-Key / command id and sent in the original
order when the connection returns, so nothing is executed twice. A command that Fleet Geeks refuses (a business rule, for
example a job that is no longer authorized) stops retrying and is listed under "Waiting to send" for the user to retry or
discard. Every screen shows an offline / waiting strip above the bottom navigation and an outbox badge in the app bar.
Messages, delivery checklists and handover offers also go through the outbox. Gate admission, release, booking requests and reviews, estimate decisions, payments, documents, signed handovers and photo uploads need a live connection because D365 (or
the file store) decides them at that moment.

## Build an APK

Requirements on the build machine (not on the D365 VM): Flutter stable 3.35 or later, Android SDK, Java 17.

```powershell
cd mobile
pwsh tools/prepare_android.ps1 -Brand      # once: creates android/ for both apps, adds INTERNET + CAMERA permissions,
                                          # generates launcher icons + splash screens and applies the vector adaptive icons
flutter analyze
flutter test packages/fg_core
cd apps/workshop_app
flutter build apk --release --dart-define=FG_API=https://<your-fleet-geeks-api> --dart-define=FG_DEV_SIGNIN=true
# APK: apps/workshop_app/build/app/outputs/flutter-apk/app-release.apk
cd ../customer_app
flutter build apk --release --dart-define=FG_API=https://<your-fleet-geeks-api> --dart-define=FG_DEV_SIGNIN=true
```

Build settings (`--dart-define`):

| Name | Default | Meaning |
|---|---|---|
| `FG_API` | `http://10.0.2.2:5098` | Fleet Geeks API base URL. `10.0.2.2` is the host machine from the Android emulator. |
| `FG_DEV_SIGNIN` | `true` | Show the development sign-in with the demo portal users. The API accepts it only in its Development environment. |
| `FG_ENV` | `Development` | Environment label. |

### Packages that need Android settings

`prepare_android.ps1` adds them to the customer app manifest: `url_launcher` (payment links) needs a `<queries>` entry for https
browsers; `open_filex` (opens downloaded PDFs from the app's temporary folder) declares media-read permissions the app does
not need, so they are removed with `tools:node="remove"`.

### Fonts

Inter (Latin) and IBM Plex Sans Arabic (Arabic) are bundled in `packages/fg_core/fonts` (SIL Open Font License 1.1, licence
texts next to the files) and declared in `packages/fg_core/pubspec.yaml`. To restore or update them:

```powershell
powershell -File mobile\tools\get_fonts.ps1
```

### App icon and splash

Sources are SVG in `assets/brand/` (original mark: a wheel with gear teeth and the road leaving it; teal tile for the
customer app, graphite tile for the workshop app, orange hub and lane). PNG renders for the generators are in
`assets/brand/png/` (re-render with `powershell -File mobile\tools\render_brand.ps1` after editing an SVG – it uses
headless Edge or Chrome). The generator settings are in each app's `pubspec.yaml` (`flutter_launcher_icons`,
`flutter_native_splash`, both dev dependencies). One command per app (or `prepare_android.ps1 -Brand` for both):

```powershell
cd mobile/apps/customer_app      # then the same in apps/workshop_app
dart run flutter_launcher_icons
dart run flutter_native_splash:create
cd ../..
powershell -File tools\apply_vector_icons.ps1   # optional: PNG-less adaptive icon (vector foreground, colour background,
                                                # monochrome for Android 13 themed icons) from assets/brand/android
```

### Trying it against the development API

1. On the VM: `cd api/src/FleetGeeks.Api; dotnet run --urls http://0.0.0.0:5098` (Development environment, dev sign-in on).
2. Prepare with `pwsh tools/prepare_android.ps1 -AllowHttp -Brand` (plain http is for development only; production uses HTTPS).
3. Build with `--dart-define=FG_API=http://<VM-IP>:5098`, install the APK, sign in as `demo.tech@example.com` (workshop) or
   `demo.admin@example.com` (customer). Demo users exist after **Generate demo data** in D365.

### Signing

`flutter build apk --release` signs with the debug key, which is enough for side-loading tests. For a store or MDM release create
an upload keystore and `android/key.properties` (both are in `.gitignore`; never commit them).

## Checks

| Check | Command | Where it runs |
|---|---|---|
| EN / AR text parity (every key in both languages, no empty text, same placeholders, every `s.t('key')` defined) | `powershell -File mobile\tools\check_i18n.ps1` | any Windows machine (also the D365 VM) |
| Static analysis | `flutter analyze` (in `mobile`) | build machine |
| Unit tests (status mapping, stages, promise countdown, number format, theme, i18n, signature controller …) | `flutter test packages/fg_core` | build machine |

## Sign-in in production

The apps keep the access token in the Android Keystore (flutter_secure_storage). Production sign-in uses the organisation's
OpenID Connect provider (blocker B-02 in `docs/BLOCKERS.md`: identity provider to be decided; B-03: a network route from phones to the API);
`AuthNotifier.signInWithToken` is the hook for it. Whatever the provider, the D365 portal user (FGPortalUserTable +
FGPortalUserRole) decides what the person can see and do.

## Status

The source was written without a Flutter toolchain on the D365 VM (by request), so it has **not been compiled or run yet**.
Run `flutter analyze` and `flutter test packages/fg_core` first on the build machine; please send any analyzer output back so it can
be fixed. The API endpoints the apps call are covered by `tests/api/api-live.ps1` against live D365.
