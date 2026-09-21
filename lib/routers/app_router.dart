import 'package:go_router/go_router.dart';

import '../widgets/home_screen.dart';
import '../widgets/splash_screen.dart';

GoRouter createAppRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
  ],
);
