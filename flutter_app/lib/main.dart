import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'pages/create_group_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/group_details_page.dart';
import 'pages/join_page.dart';
import 'pages/landing_page.dart';
import 'pages/participant_event_page.dart';
import 'pages/sign_in_page.dart';
import 'services/auth_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await SupabaseService.initialize();
  runApp(const SecretSantaApp());
}

final _router = GoRouter(
  refreshListenable: GoRouterRefreshStream(AuthService.onAuthStateChange),
  redirect: (context, state) {
    final signedIn = AuthService.isSignedIn;
    final path = state.uri.path;
    final isAuthRoute = path == '/sign-in';
    final isPublicRoute = path == '/' || path == '/join' || isAuthRoute;

    if (!signedIn && !isPublicRoute) return '/sign-in';
    if (signedIn && isAuthRoute) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) =>
          AuthService.isSignedIn ? const DashboardPage() : const LandingPage(),
    ),
    GoRoute(
      path: '/sign-in',
      builder: (context, state) => const SignInPage(),
    ),
    GoRoute(
      path: '/create',
      builder: (context, state) => const CreateGroupPage(),
    ),
    GoRoute(
      path: '/group/:id',
      builder: (context, state) =>
          GroupDetailsPage(groupId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/event/:id',
      builder: (context, state) =>
          ParticipantEventPage(groupId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/join',
      builder: (context, state) => JoinPage(
        shareCode: state.uri.queryParameters['code'],
        revealCode: state.uri.queryParameters['reveal'],
      ),
    ),
  ],
);

class SecretSantaApp extends StatelessWidget {
  const SecretSantaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Secret Santa Organizer',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.red)),
      routerConfig: _router,
    );
  }
}

/// Bridges a Stream into a Listenable so go_router can react to Supabase
/// auth state changes (sign in/out) and re-run its redirect logic.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final dynamic _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
