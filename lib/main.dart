// lib/main.dart — FINAL v4 with all social routes
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:app_links/app_links.dart';

import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/iap_listener_service.dart';
import 'services/auth_provider.dart';
import 'services/notification_service.dart';
import 'services/social_api_service.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/email_verify_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/quiz/quiz_screen.dart';
import 'screens/quiz/result_screen.dart';
import 'screens/leaderboard/leaderboard_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/lessons/lesson_screen.dart';
import 'screens/store/store_screen.dart';
import 'screens/gdpr/data_export_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/quiz_preferences_screen.dart';
import 'screens/duel/duel_screen.dart';
import 'screens/duel/invitations_screen.dart';
import 'screens/challenge/challenge_screen.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/auth/reset_password_screen.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
    await Firebase.initializeApp();
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    const enabled = bool.fromEnvironment(
        'CRASHLYTICS_ENABLED', defaultValue: true);
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(enabled);
    await FirebaseCrashlytics.instance
        .log('App launch: ${DateTime.now().toIso8601String()}');
    await NotificationService.init();
    runApp(NipinoManabuApp(navigatorKey: _navigatorKey));
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class NipinoManabuApp extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const NipinoManabuApp({super.key, required this.navigatorKey});
  @override State<NipinoManabuApp> createState() => _NipinoManabuAppState();
}

class _NipinoManabuAppState extends State<NipinoManabuApp> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    ApiService.onSessionExpired = _handleSessionExpired;
    _initDeepLinks();
    IapListenerService.instance.start(widget.navigatorKey);
  }

  void _handleSessionExpired() {
    widget.navigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) _handleLink(initial);
    } catch (_) {}
    _linkSub = appLinks.uriLinkStream.listen(_handleLink,
        onError: (e) => FirebaseCrashlytics.instance
            .recordError(e, null, reason: 'deep_link_error'));
  }

  void _handleLink(Uri uri) {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;

    // Custom scheme (nipinomanabu://xyz/...) — the "host" segment carries
    // the route name, e.g. nipinomanabu://duel/{roomUuid}.
    if (uri.scheme == 'nipinomanabu') {
      _routeByName(nav, uri.host, uri.pathSegments, uri.queryParameters);
      return;
    }

    // HTTPS App Links / Universal Links (https://nipino-manabu.com/...).
    // uri.host here is always the domain — the route lives in uri.path, NOT
    // uri.host. (Previously this switched on uri.host for these links too,
    // so no https link ever matched and every one fell through to /home.)
    final segments = uri.pathSegments; // e.g. ['reset-password'] or ['app','duel','abc']
    final name = segments.isNotEmpty
        ? (segments.first == 'app' && segments.length > 1 ? segments[1] : segments.first)
        : '';
    final rest = segments.isNotEmpty && segments.first == 'app'
        ? segments.skip(2).toList()
        : segments.skip(1).toList();
    _routeByName(nav, name, rest, uri.queryParameters);
  }

  // Shared dispatch for both the custom scheme and https App Links, once
  // each has been normalized to a route "name" + remaining path segments.
  void _routeByName(NavigatorState nav, String name, List<String> segments,
      Map<String, String> query) {
    switch (name) {
      case 'email-verified':
        nav.pushNamedAndRemoveUntil('/home', (_) => false); break;
      case 'reset-password':
        nav.push(MaterialPageRoute(
            builder: (_) => ResetPasswordScreen(token: query['token'] ?? '')));
        break;
      case 'duel':
        final uuid = segments.isNotEmpty ? segments.first : null;
        if (uuid != null) {
          nav.push(MaterialPageRoute(
              builder: (_) => DuelLobbyScreen(roomUuid: uuid)));
        }
        break;
      case 'invite':
        final code = segments.isNotEmpty ? segments.first : null;
        if (code != null) {
          // Most taps on this link are a brand-new install with no session
          // yet, so claiming immediately just 401s and silently drops the
          // code. Persist it either way and let AuthProvider retry the
          // claim right after register/login succeeds.
          ApiService.savePendingReferralCode(code);
          ApiService.getToken().then((token) {
            if (token != null) SocialApiService.claimReferral(code);
          });
        }
        break;
      case 'challenge':
        nav.pushNamed('/challenges'); break;
      case 'quiz':
        nav.pushNamed('/quiz', arguments: {
          'level':    query['level']    ?? 'N3',
          'category': query['category'] ?? 'kanji',
        }); break;
      case 'leaderboard':
        nav.pushNamed('/leaderboard'); break;
      default:
        nav.pushNamed('/home');
    }
  }

  @override
  void dispose() { _linkSub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AuthProvider()..checkAuth()),
      ],
      child: MaterialApp(
        title: 'Nipino-Manabu',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        navigatorKey: widget.navigatorKey,
        initialRoute: '/splash',
        routes: {
          '/splash':           (_) => const SplashScreen(),
          '/login':            (_) => const LoginScreen(),
          '/register':         (_) => const RegisterScreen(),
          '/forgot-password':  (_) => const ForgotPasswordScreen(),
          '/verify-email':     (_) => const EmailVerifyScreen(),
          '/home':             (_) => const HomeScreen(),
          '/lessons':          (_) => const LessonScreen(),
          '/quiz':             (_) => const QuizScreen(),
          '/result':           (_) => const ResultScreen(),
          '/leaderboard':      (_) => const LeaderboardScreen(),
          '/profile':          (_) => const ProfileScreen(),
          '/store':            (_) => const StoreScreen(),
          '/data-export':      (_) => const DataExportScreen(),
          '/settings':         (_) => const SettingsScreen(),
          '/quiz-preferences': (_) => const QuizPreferencesScreen(),
          '/duels':            (_) => const DuelHubScreen(),
          '/invitations':      (_) => const InvitationsScreen(),
          '/challenges':       (_) => const ChallengeHubScreen(),
          '/referral':         (_) => const ReferralScreen(),
          '/admin':            (_) => const AdminScreen(),
        },
        navigatorObservers: [_CrashlyticsObserver()],
      ),
    );
  }
}

class _CrashlyticsObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    final name = route.settings.name;
    if (name != null)
      FirebaseCrashlytics.instance.log('screen: $name');
  }
}

class AppNavigatorKey {
  static GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;
}
