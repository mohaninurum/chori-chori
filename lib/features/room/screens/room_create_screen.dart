import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../models/room_model.dart';
import '../providers/room_provider.dart';

class RoomCreateScreen extends ConsumerStatefulWidget {
  const RoomCreateScreen({super.key});

  @override
  ConsumerState<RoomCreateScreen> createState() => _RoomCreateScreenState();
}

class _RoomCreateScreenState extends ConsumerState<RoomCreateScreen> {
  final _nameController = TextEditingController();
  int _expiryMinutes = 60; // default 1 hour

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _generateRoomId() {
    // Avoid easily confused characters: 0/O, 1/I
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  void _createRoom() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room name')),
      );
      return;
    }

    final now = DateTime.now();
    final room = Room(
      id: _generateRoomId(),
      name: _nameController.text.trim(),
      createdAt: now,
      expiresAt: now.add(Duration(minutes: _expiryMinutes)),
    );

    final success = await ref.read(currentRoomProvider.notifier).createAndJoinRoom(room);
    if (success && mounted) {
      Clipboard.setData(ClipboardData(text: room.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room created! Code "${room.id}" copied to clipboard.'),
          backgroundColor: AppTheme.primaryNeon,
          duration: const Duration(seconds: 3),
        ),
      );
      context.go(Routes.chat); // Navigate to chat on success
    } else if (mounted) {
      final roomState = ref.read(currentRoomProvider);
      String errorMsg = 'Failed to create room';
      if (roomState.hasError) {
        final err = roomState.error;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(currentRoomProvider);
    final isLoading = roomState is AsyncLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Private Room')),
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
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Room Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.meeting_room, color: AppTheme.primaryNeon),
                ),
              ),
              const SizedBox(height: 24),
              Text('Room Expiry', style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: _expiryMinutes.toDouble(),
                min: 5,
                max: 1440,
                divisions: 20,
                activeColor: AppTheme.primaryNeon,
                label: '$_expiryMinutes mins',
                onChanged: (val) {
                  setState(() {
                    _expiryMinutes = val.toInt();
                  });
                },
              ),
              Text(
                'Room will self-destruct in $_expiryMinutes minutes.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.secondaryNeon),
              ),
              const SizedBox(height: 48),
              if (isLoading)
                const Center(child: CircularProgressIndicator(color: AppTheme.primaryNeon))
              else
                ElevatedButton(
                  onPressed: _createRoom,
                  child: const Text('Initialize Safe Room', style: TextStyle(fontSize: 16)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
