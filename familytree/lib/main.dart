import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_colors.dart';
import 'core/services/firebase_service.dart';
import 'providers/auth_provider.dart';
import 'providers/family_group_provider.dart';
import 'providers/family_provider.dart';
import 'views/auth/master_login_screen.dart';
import 'views/auth/master_register_screen.dart';
import 'views/auth/member_login_screen.dart';
import 'views/dashboard/master_dashboard.dart';
import 'views/dashboard/member_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Configure Firestore offline persistence settings
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  
  // Initialize push notification services
  try {
    await FirebaseService.instance.initializeNotifications();
  } catch (e) {
    debugPrint('Failed to initialize notification system: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FamilyGroupProvider()),
        ChangeNotifierProvider(create: (_) => FamilyProvider()),
      ],
      child: const FamilyTreeApp(),
    ),
  );
}

class FamilyTreeApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const FamilyTreeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Family Tree',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Tracks which familyId we're currently listening to, preventing
  /// duplicate startListening calls on every rebuild.
  String? _listeningFamilyId;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // 1. Show splash while checking for an existing session or restoring operations
    if (auth.isLoading) {
      return const _SplashScreen();
    }

    // 2. Handle unexpected backend/network errors safely without dropping down to Login
    if (auth.status == AuthStatus.error) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                const SizedBox(height: 16),
                const Text(
                  'Authentication Sync Error',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  auth.errorMessage ?? 'Unknown session initialization error.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => auth.signOut(),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Back to Login', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 3. Handle Authenticated Session Routing cleanly
    if (auth.status == AuthStatus.authenticated) {
      if (auth.isMaster) {
        // Stop member streams if we were listening before
        _stopMemberStreams();
        return const MasterDashboard();
      } else {
        // Family Admin AND regular members both use MemberDashboard.
        // Start listening only once per familyId.
        final familyId = auth.currentUser?.familyId ?? '';
        if (familyId.isNotEmpty && _listeningFamilyId != familyId) {
          _listeningFamilyId = familyId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.read<FamilyProvider>().startListening(familyId);
            }
          });
        }
        return const MemberDashboard();
      }
    }

    // 4. Fallback strictly to Logged Out forms if status is explicitly Unauthenticated
    _stopMemberStreams();
    return const LoginChooser();
  }

  void _stopMemberStreams() {
    if (_listeningFamilyId != null) {
      _listeningFamilyId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<FamilyGroupProvider>().stopListening();
          context.read<FamilyProvider>().stopListening();
        }
      });
    }
  }
}

enum _AuthScreen { memberLogin, masterLogin, masterRegister }

class LoginChooser extends StatefulWidget {
  const LoginChooser({super.key});
  @override
  State<LoginChooser> createState() => _LoginChooserState();
}

class _LoginChooserState extends State<LoginChooser> {
  _AuthScreen _screen = _AuthScreen.memberLogin;

  @override
  Widget build(BuildContext context) {
    switch (_screen) {
      case _AuthScreen.memberLogin:
        return MemberLoginScreen(
          onSwitchToMaster: () =>
              setState(() => _screen = _AuthScreen.masterLogin),
        );
      case _AuthScreen.masterLogin:
        return MasterLoginScreen(
          onSwitchToMember: () =>
              setState(() => _screen = _AuthScreen.memberLogin),
          onSwitchToRegister: () =>
              setState(() => _screen = _AuthScreen.masterRegister),
        );
      case _AuthScreen.masterRegister:
        return MasterRegisterScreen(
          onSwitchToLogin: () =>
              setState(() => _screen = _AuthScreen.masterLogin),
        );
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_rounded, size: 80, color: Colors.white),
            SizedBox(height: 20),
            Text('Family Tree',
                style: TextStyle(
                    color: Colors.white, fontSize: 28,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 40),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
