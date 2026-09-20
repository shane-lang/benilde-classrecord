import 'package:flutter/material.dart';

import 'screens/accept_invite_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

bool _handlingExpiry = false;

Future<void> _onSessionExpired() async {
  if (_handlingExpiry) return;
  _handlingExpiry = true;
  try {

    final wasAdmin = AuthService.instance.currentUser?.isAdmin ?? false;
    await AuthService.instance.signOut();
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil(
        wasAdmin ? '/admin-login' : '/login', (_) => false);
    messengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Your session has expired. Log in again to continue.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } finally {
    _handlingExpiry = false;
  }
}

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  final signedIn = await AuthService.instance.restoreSession();
  final isAdmin = AuthService.instance.currentUser?.isAdmin ?? false;

  ApiClient.onSessionExpired = _onSessionExpired;

  runApp(ClassRecordApp(startSignedIn: signedIn, startAsAdmin: isAdmin));
}

class ClassRecordApp extends StatelessWidget {
  final bool startSignedIn;
  final bool startAsAdmin;

  const ClassRecordApp({
    super.key,
    this.startSignedIn = false,
    this.startAsAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Benilde ClassRecord',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: AppTheme.light,
      initialRoute: !startSignedIn
          ? '/login'
          : (startAsAdmin ? '/admin' : '/dashboard'),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/accept-invite': (context) => const AcceptInviteScreen(),
        '/admin-login': (context) => const AdminLoginScreen(),
        '/admin': (context) => const AdminScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}