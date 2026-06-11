import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/event_log_screen.dart';
import 'screens/identity_debug_screen.dart';
import 'screens/learning_screen.dart';
import 'screens/live_view_screen.dart';
import 'screens/security/auth_gate_screen.dart';
import 'screens/settings_screen.dart';
import 'services/pipeline/vision_pipeline_controller.dart';
import 'services/pipeline/vision_scope.dart';
import 'services/security/app_lock_service.dart';
import 'services/security/biometric_auth_service.dart';
import 'services/security/security_scope.dart';
import 'widgets/app_logo.dart';

class SentinelVisionApp extends StatefulWidget {
  const SentinelVisionApp({super.key});

  @override
  State<SentinelVisionApp> createState() => _SentinelVisionAppState();
}

class _SentinelVisionAppState extends State<SentinelVisionApp> {
  late final BiometricAuthService _authService;
  late final AppLockService _appLockService;

  @override
  void initState() {
    super.initState();
    _authService = BiometricAuthService();
    _appLockService = AppLockService(authService: _authService);
  }

  @override
  void dispose() {
    _appLockService.dispose();
    _authService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SecurityScope(
      authService: _authService,
      appLockService: _appLockService,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sentinel Vision Mobile',
        theme: _buildTheme(),
        home: AuthGateScreen(
          authService: _authService,
          appLockService: _appLockService,
          child: const _AuthenticatedVisionApp(),
        ),
      ),
    );
  }

  ThemeData _buildTheme() {
    const background = Color(0xFF07111B);
    const surface = Color(0xFF101C28);
    const elevated = Color(0xFF162636);
    const primary = Color(0xFF3ED4D3);
    const secondary = Color(0xFFFF9A3D);
    const outline = Color(0xFF274154);

    final scheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: primary,
      secondary: secondary,
      surface: surface,
      error: Color(0xFFFF6E6E),
      onPrimary: Color(0xFF031417),
      onSecondary: Color(0xFF241100),
      onSurface: Color(0xFFE8F2F7),
      outline: outline,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: 'monospace',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Color(0xFFE8F2F7),
      ),
      cardTheme: CardThemeData(
        color: elevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: outline),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0C1722),
        indicatorColor: primary.withValues(alpha: 0.18),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevated,
        selectedColor: primary.withValues(alpha: 0.16),
        disabledColor: elevated,
        side: const BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: const TextStyle(
          color: Color(0xFFE8F2F7),
          fontWeight: FontWeight.w600,
        ),
      ),
      sliderTheme: const SliderThemeData(
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Color(0xFFE8F2F7),
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Color(0xFFE8F2F7),
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Color(0xFFE8F2F7),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Color(0xFFB6C9D8),
          height: 1.4,
        ),
        bodySmall: TextStyle(fontSize: 12, color: Color(0xFF91A7B8)),
      ),
    );
  }
}

class _AuthenticatedVisionApp extends StatefulWidget {
  const _AuthenticatedVisionApp();

  @override
  State<_AuthenticatedVisionApp> createState() =>
      _AuthenticatedVisionAppState();
}

class _AuthenticatedVisionAppState extends State<_AuthenticatedVisionApp> {
  late final VisionPipelineController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VisionPipelineController();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisionScope(controller: _controller, child: const _AppShell());
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: SentinelLogoHeader(compact: true),
            ),
            Expanded(child: _screenForIndex(_index)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          setState(() {
            _index = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Console',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Learning',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Identity',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Events',
          ),
        ],
      ),
    );
  }

  Widget _screenForIndex(int index) {
    return switch (index) {
      0 => const LiveViewScreen(),
      1 => const DashboardScreen(),
      2 => const LearningScreen(),
      3 => const IdentityDebugScreen(),
      4 => const SettingsScreen(),
      _ => const EventLogScreen(),
    };
  }
}
