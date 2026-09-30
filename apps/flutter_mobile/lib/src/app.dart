import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import 'screens/auth_screen.dart';
import 'screens/document_text_screen.dart';
import 'screens/jury_screen.dart';
import 'screens/legal_document_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/project_detail_screen.dart';
import 'screens/profile_preferences_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/report_screen.dart';
import 'screens/training_screen.dart';
import 'screens/training_history_screen.dart';
import 'theme.dart';
import 'widgets.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authControllerProvider);
  return GoRouter(
    initialLocation: '/projects',
    refreshListenable: auth,
    redirect: (context, state) {
      if (!auth.initialized) return null;
      final signingIn = state.matchedLocation == '/login';
      if (!auth.authenticated) {
        if (signingIn) return null;
        return Uri(
          path: '/login',
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      final onboarding = state.matchedLocation == '/onboarding';
      if (auth.needsOnboarding && !onboarding) return '/onboarding';
      if (!auth.needsOnboarding && (signingIn || onboarding)) {
        final from = state.uri.queryParameters['from'];
        if (signingIn && from != null && from.startsWith('/')) return from;
        return '/projects';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'preferences',
            builder: (context, state) => const ProfilePreferencesScreen(),
          ),
          GoRoute(
            path: 'privacy',
            builder: (context, state) =>
                const LegalDocumentScreen(type: LegalDocumentType.privacy),
          ),
          GoRoute(
            path: 'terms',
            builder: (context, state) =>
                const LegalDocumentScreen(type: LegalDocumentType.terms),
          ),
        ],
      ),
      GoRoute(
        path: '/projects',
        builder: (context, state) => const ProjectsScreen(),
      ),
      GoRoute(
        path: '/projects/:id',
        builder: (context, state) =>
            ProjectDetailScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/documents/:documentId',
        builder: (context, state) =>
            DocumentTextScreen(documentId: state.pathParameters['documentId']!),
      ),
      GoRoute(
        path: '/projects/:id/training',
        builder: (context, state) =>
            TrainingScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/history',
        builder: (context, state) =>
            TrainingHistoryScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/jury',
        builder: (context, state) => JuryScreen(
          projectId: state.pathParameters['id']!,
          sessionId: state.uri.queryParameters['session'],
          autoStart: state.uri.queryParameters['autostart'] == '1',
        ),
      ),
      GoRoute(
        path: '/reports/:sessionId',
        builder: (context, state) => ReportScreen(
          sessionId: state.pathParameters['sessionId']!,
          generate: state.uri.queryParameters['generate'] == '1',
        ),
      ),
    ],
  );
});

class SpeechMirrorApp extends ConsumerStatefulWidget {
  const SpeechMirrorApp({super.key});
  @override
  ConsumerState<SpeechMirrorApp> createState() => _SpeechMirrorAppState();
}

class _SpeechMirrorAppState extends ConsumerState<SpeechMirrorApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider).restore());
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: speechMirrorTheme(),
        home: const Scaffold(body: Center(child: _BrandLoader())),
      );
    }
    return MaterialApp.router(
      title: '言镜 SpeechMirror',
      debugShowCheckedModeBanner: false,
      theme: speechMirrorTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _BrandLoader extends StatelessWidget {
  const _BrandLoader();
  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppLogo(size: 68),
      SizedBox(height: 14),
      Text(
        '言镜',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
      SizedBox(height: 18),
      SizedBox(
        width: 32,
        height: 2,
        child: LinearProgressIndicator(
          color: AppColors.jade,
          backgroundColor: AppColors.paperStrong,
        ),
      ),
    ],
  );
}
