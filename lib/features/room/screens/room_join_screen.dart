import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/room_provider.dart';

class RoomJoinScreen extends ConsumerStatefulWidget {
  const RoomJoinScreen({super.key});

  @override
  ConsumerState<RoomJoinScreen> createState() => _RoomJoinScreenState();
}

class _RoomJoinScreenState extends ConsumerState<RoomJoinScreen> {
  final _idController = TextEditingController();
  final _passcodeController = TextEditingController();

  @override
  void dispose() {
    _idController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  void _joinRoom() async {
    if (_idController.text.isEmpty || _passcodeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Room ID and Passcode')),
      );
      return;
    }

    final success = await ref.read(currentRoomProvider.notifier).joinRoom(
      _idController.text.trim().toUpperCase(), 
      _passcodeController.text.trim()
    );

    if (success && mounted) {
      context.go(Routes.chat); // Navigate to chat on success
    } else if (mounted) {
      final state = ref.read(currentRoomProvider);
      final errorMsg = state.hasError ? state.error.toString() : 'Failed to join room';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(currentRoomProvider);
    final isLoading = roomState is AsyncLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Join Safe Room')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.backgroundDark, AppTheme.backgroundLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              TextField(
                controller: _idController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Room ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key, color: AppTheme.secondaryNeon),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passcodeController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Secret Passcode',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock, color: AppTheme.secondaryNeon),
                ),
              ),
              const SizedBox(height: 48),
              if (isLoading)
                const Center(child: CircularProgressIndicator(color: AppTheme.secondaryNeon))
              else
                ElevatedButton(
                  onPressed: _joinRoom,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryNeon),
                  child: const Text('Enter Room', style: TextStyle(fontSize: 16, color: Colors.black87)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
