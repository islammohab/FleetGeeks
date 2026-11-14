import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/book_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/compliance_screen.dart';
import 'screens/fault_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inspection_screen.dart';
import 'screens/more_screen.dart';
import 'screens/order_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/pool_screen.dart';
import 'screens/qr_scan_page.dart';
import 'screens/usage_screen.dart';
import 'screens/vehicle_screen.dart';
import 'screens/vehicles_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedServer();
  runApp(ProviderScope(
    overrides: [
      // The server dialog can read the address from a QR code.
      serverQrScanProvider.overrideWithValue(
        (context) => Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => Consumer(
              builder: (context, ref, _) {
                final s = ref.watch(stringsProvider);
                return QrScanPage(title: s.t('serverScanQr'), hint: s.t('serverScanHint'));
              },
            ),
          ),
        ),
      ),
    ],
    child: const CustomerApp(),
  ));
}

/// Prompt 3 (C1): the sign-in lists the active customer, driver and internal fleet users read from D365
/// (GET /dev/users?portal=customer); this list is shown only when the API cannot be reached.
const fallbackUsers = {
  'demo.admin@example.com': 'Customer admin (Demo)',
  'demo.driver@example.com': 'Driver (Demo)',
  'demo.fleetb@example.com': 'Fleet manager, customer B (Demo)',
  'demo.internal@example.com': 'Internal fleet manager (Demo)',
};

/// Tabs of the bottom navigation (path, icon, label key).
const _tabs = <(String, IconData, String)>[
  ('/', FgIcons.home, 'home'),
  ('/vehicles', FgIcons.vehicles, 'vehicles'),
  ('/book', FgIcons.book, 'bookShort'),
  ('/orders', FgIcons.orders, 'ordersShort'),
  ('/more', FgIcons.more, 'more'),
];

Page<void> _tab(Widget child) => NoTransitionPage<void>(child: child);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    // D-110: an incoming link (app link of the portal or fleetgeeks://) opens its screen; unknown links go home
    redirect: (context, state) {
      final uri = state.uri;
      if (uri.scheme == 'fleetgeeks' || (uri.hasScheme && uri.scheme.startsWith('http'))) return FgDeepLinks.route(uri) ?? '/';
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', pageBuilder: (context, state) => _tab(const HomeScreen())),
          GoRoute(path: '/vehicles', pageBuilder: (context, state) => _tab(const VehiclesScreen())),
          GoRoute(path: '/book', pageBuilder: (context, state) => _tab(BookScreen(vehicleId: state.uri.queryParameters['vehicle']))),
          GoRoute(path: '/orders', pageBuilder: (context, state) => _tab(const OrdersScreen())),
          GoRoute(path: '/more', pageBuilder: (context, state) => _tab(const MoreScreen())),
        ],
      ),
      GoRoute(path: '/vehicles/:id', builder: (context, state) => VehicleScreen(vehicleId: state.pathParameters['id']!)),
      GoRoute(path: '/inspection', builder: (context, state) => const InspectionScreen()),
      GoRoute(path: '/compliance', builder: (context, state) => const ComplianceScreen()),
      GoRoute(path: '/fault', builder: (context, state) => FaultScreen(vehicleId: state.uri.queryParameters['vehicle'])),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) => OrderScreen(orderId: state.pathParameters['id']!),
        routes: [
          GoRoute(path: 'messages', builder: (context, state) => MessagesScreen(orderId: state.pathParameters['id']!, mySide: 'Customer')),
        ],
      ),
      GoRoute(path: '/bookings/:id', builder: (context, state) => BookingScreen(appointmentId: state.pathParameters['id']!)),
      GoRoute(path: '/outbox', builder: (context, state) => const OutboxScreen()),
      GoRoute(path: '/notifications', builder: (context, state) => NotificationsScreen(open: (context, route) => context.push(route))),
      GoRoute(path: '/usage', builder: (context, state) => UsageScreen(vehicleId: state.uri.queryParameters['vehicle'])),
      GoRoute(path: '/pool', builder: (context, state) => const PoolScreen()),
    ],
  );
});

class CustomerApp extends ConsumerWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final auth = ref.watch(authProvider);
    final s = ref.watch(stringsProvider);
    const delegates = [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate];
    const locales = [Locale('en'), Locale('ar')];
    final light = fgTheme(Brightness.light, lang: locale.languageCode);
    final dark = fgTheme(Brightness.dark, lang: locale.languageCode);

    final user = auth.value;
    if (auth.isLoading || user == null || !user.isCustomerSide) {
      return MaterialApp(
        title: s.t('appCustomer'),
        debugShowCheckedModeBanner: false,
        builder: fgAppFrame,
        theme: light,
        darkTheme: dark,
        locale: locale,
        supportedLocales: locales,
        localizationsDelegates: delegates,
        home: auth.isLoading && user == null
            ? const FgLoadingScreen()
            : user == null
                ? DevSignInScreen(title: s.t('appCustomer'), portal: 'customer', fallbackUsers: fallbackUsers)
                : NoAccessScreen(title: s.t('appCustomer')),
      );
    }
    return MaterialApp.router(
      title: s.t('appCustomer'),
      debugShowCheckedModeBanner: false,
        builder: fgAppFrame,
      theme: light,
      darkTheme: dark,
      locale: locale,
      supportedLocales: locales,
      localizationsDelegates: delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Bottom navigation (Home, Vehicles, Book, Orders, More) with the offline / outbox strip above it.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final waiting = ref.watch(outboxProvider).value?.length ?? 0;
    final unread = ref.watch(unreadMessagesProvider).value?.n('total').round() ?? 0;
    final index = _tabs.indexWhere((t) => t.$1 == location);
    return Scaffold(
      body: child,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        OfflineBanner(onOpenOutbox: () => context.push('/outbox')),
        NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) {
            FgHaptics.tap();
            context.go(_tabs[i].$1);
          },
          destinations: [
            for (final t in _tabs)
              NavigationDestination(
                icon: t.$1 == '/more' && waiting > 0
                    ? Badge(label: Text('$waiting'), child: Icon(t.$2))
                    : (t.$1 == '/orders' && unread > 0 ? Badge(label: Text('$unread'), child: Icon(t.$2)) : Icon(t.$2)),
                label: s.t(t.$3),
              ),
          ],
        ),
      ]),
    );
  }
}
