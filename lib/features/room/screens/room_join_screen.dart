import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
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

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  void _joinRoom() async {
    final input = _idController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter Room ID or Room Name')));
      return;
    }

    final success = await ref
        .read(currentRoomProvider.notifier)
        .joinRoom(input);

    if (success && mounted) {
      context.go(Routes.chat); // Navigate to chat on success
    } else if (mounted) {
      final state = ref.read(currentRoomProvider);
      String errorMsg = 'Failed to join room!';
      if (state.hasError) {
        final err = state.error;
        if (err is FirebaseException) {
          if (err.code == 'permission-denied') {
            errorMsg = 'Firestore Permission Denied. Check Firestore security rules in Firebase Console.';
          } else {
            errorMsg = 'Firebase Error: ${err.message ?? err.code}';
          }
        } else {
          errorMsg = err.toString();
        }
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: Colors.redAccent));
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
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: 'Room ID or Room Name',
                  hintText: 'Enter 6-character code (e.g. 7X9K2P)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.vpn_key,
                    color: AppTheme.secondaryNeon,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste, color: AppTheme.secondaryNeon),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        setState(() {
                          _idController.text = data!.text!.trim().toUpperCase();
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 48),
              if (isLoading)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.secondaryNeon,
                  ),
                )
              else
                ElevatedButton(
                  onPressed: _joinRoom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryNeon,
                  ),
                  child: const Text(
                    'Enter Room',
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
