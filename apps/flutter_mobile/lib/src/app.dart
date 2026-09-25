import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import 'screens/auth_screen.dart';
import 'screens/document_text_screen.dart';
import 'screens/jury_screen.dart';
import 'screens/project_detail_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/report_screen.dart';
import 'screens/training_screen.dart';
import 'screens/training_history_screen.dart';
import 'theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authControllerProvider);
  return GoRouter(
    initialLocation: '/projects',
    refreshListenable: auth,
    redirect: (context, state) {
      if (!auth.initialized) return null;
      final signingIn = state.matchedLocation == '/login';
      if (!auth.authenticated) return signingIn ? null : '/login';
      if (signingIn) return '/projects';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const AuthScreen()),
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
        ),
      ),
      GoRoute(
        path: '/reports/:sessionId',
        builder: (context, state) =>
            ReportScreen(sessionId: state.pathParameters['sessionId']!),
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
      Text(
        '言镜',
        style: TextStyle(
          fontFamily: 'Songti SC',
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      SizedBox(height: 18),
      SizedBox(
        width: 32,
        height: 2,
        child: LinearProgressIndicator(
          color: AppColors.vermilion,
          backgroundColor: AppColors.paperStrong,
        ),
      ),
    ],
  );
}
