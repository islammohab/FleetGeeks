import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/board_screen.dart';
import 'screens/bookings_review_screen.dart';
import 'screens/gate_screen.dart';
import 'screens/job_screen.dart';
import 'screens/mobility_screen.dart';
import 'screens/more_screen.dart';
import 'screens/order_screen.dart';
import 'screens/parts_screen.dart';
import 'screens/tasks_screen.dart';

void main() => runApp(const ProviderScope(child: WorkshopApp()));

/// Demo workshop users created by "Generate demo data" in D365.
const demoUsers = {
  'demo.advisor@example.com': 'Service advisor + gate (Demo)',
  'demo.tech@example.com': 'Technician + QC + stores (Demo)',
};

Page<void> _tab(Widget child) => NoTransitionPage<void>(child: child);

/// Signed-in navigation (sign-in itself is handled before the router is shown).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', pageBuilder: (context, state) => _tab(const BoardScreen())),
          GoRoute(path: '/gate', pageBuilder: (context, state) => _tab(const GateScreen())),
          GoRoute(path: '/tasks', pageBuilder: (context, state) => _tab(const TasksScreen())),
          GoRoute(path: '/parts', pageBuilder: (context, state) => _tab(const PartsScreen())),
          GoRoute(path: '/more', pageBuilder: (context, state) => _tab(const MoreScreen())),
        ],
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) => OrderScreen(orderId: state.pathParameters['id']!),
        routes: [
          GoRoute(path: 'messages', builder: (context, state) => MessagesScreen(orderId: state.pathParameters['id']!, mySide: 'Workshop')),
          GoRoute(
            path: 'jobs/:line',
            builder: (context, state) => JobScreen(orderId: state.pathParameters['id']!, line: state.pathParameters['line']!),
          ),
        ],
      ),
      GoRoute(path: '/outbox', builder: (context, state) => const OutboxScreen()),
      GoRoute(path: '/mobility', builder: (context, state) => const MobilityScreen()),
      GoRoute(path: '/bookings', builder: (context, state) => const BookingsReviewScreen()),
    ],
  );
});

class WorkshopApp extends ConsumerWidget {
  const WorkshopApp({super.key});

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
    if (auth.isLoading || user == null || !user.isWorkshopStaff) {
      return MaterialApp(
        title: s.t('appWorkshop'),
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        locale: locale,
        supportedLocales: locales,
        localizationsDelegates: delegates,
        home: auth.isLoading && user == null
            ? const FgLoadingScreen()
            : user == null
                ? DevSignInScreen(title: s.t('appWorkshop'), subtitle: s.t('workshopTagline'), users: demoUsers)
                : NoAccessScreen(title: s.t('appWorkshop')),
      );
    }
    return MaterialApp.router(
      title: s.t('appWorkshop'),
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      locale: locale,
      supportedLocales: locales,
      localizationsDelegates: delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Bottom navigation: Board, Gate (gate / advisor roles), Tasks, Parts (stores), More; offline / outbox strip above it.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final user = ref.watch(authProvider).value;
    final waiting = ref.watch(outboxProvider).value?.length ?? 0;
    final tabs = <(String, IconData, String)>[
      ('/', FgIcons.board, s.t('board')),
      if (user?.has(['Gate', 'Advisor']) ?? false) ('/gate', FgIcons.gate, s.t('gate')),
      ('/tasks', FgIcons.tasks, s.t('tasks')),
      if (user?.has(['Stores']) ?? false) ('/parts', FgIcons.parts, s.t('parts')),
      ('/more', FgIcons.more, s.t('more')),
    ];
    final index = tabs.indexWhere((t) => t.$1 == location);
    return Scaffold(
      body: child,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        OfflineBanner(onOpenOutbox: () => context.push('/outbox')),
        NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) {
            FgHaptics.tap();
            context.go(tabs[i].$1);
          },
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: t.$1 == '/more' && waiting > 0 ? Badge(label: Text('$waiting'), child: Icon(t.$2)) : Icon(t.$2),
                label: t.$3,
              ),
          ],
        ),
      ]),
    );
  }
}
