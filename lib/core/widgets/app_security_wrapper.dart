import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSecurityWrapper extends StatefulWidget {
  final Widget child;

  const AppSecurityWrapper({super.key, required this.child});

  @override
  State<AppSecurityWrapper> createState() => _AppSecurityWrapperState();
}

class _AppSecurityWrapperState extends State<AppSecurityWrapper> with WidgetsBindingObserver {
  bool _isAuthenticated = false;
  bool _isBackgroundDataHidden = false;
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _secureScreen();
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _secureScreen() async {
    if (Platform.isAndroid) {
      // Prevents screenshots and screen recording on Android
      await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    }
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasPinSetup = prefs.getBool('has_pin_setup') ?? false;

    if (!hasPinSetup) {
      // Skip auth if not setup yet (or force them to set it up later)
      setState(() => _isAuthenticated = true);
      return;
    }

    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (canAuthenticate) {
        final bool didAuthenticate = await _auth.authenticate(
          localizedReason: 'Please authenticate to access Chori Chori',
        );
        setState(() {
          _isAuthenticated = didAuthenticate;
        });
      } else {
        // Fallback to true if device lacks hardware, though we'd normall require a custom PIN
        setState(() => _isAuthenticated = true);
      }
    } catch (e) {
      setState(() => _isAuthenticated = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      setState(() {
        _isBackgroundDataHidden = true;
      });
    } else if (state == AppLifecycleState.resumed) {
      setState(() {
        _isBackgroundDataHidden = false;
      });
      // Optionally re-trigger _checkAuth() here if needed upon return
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Icon(Icons.lock, size: 64, color: Colors.pinkAccent),
          ),
        ),
      );
    }

    return Stack(
      children: [
        widget.child,
        if (_isBackgroundDataHidden)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: const ColoredBox(color: Colors.black45),
            ),
          ),
      ],
    );
  }
}
