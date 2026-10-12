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
  int _expiryMinutes = 120; // default 2 hours

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes mins';
    } else {
      final hours = minutes ~/ 60;
      final remainingMins = minutes % 60;
      if (remainingMins == 0) {
        return '$hours Hour${hours > 1 ? 's' : ''}';
      } else {
        return '$hours hr $remainingMins min';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _createRoom() async {
    final rawName = _nameController.text.trim();
    if (rawName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room name')),
      );
      return;
    }

    // Room ID is now generated directly from the room name so no separate ID is needed!
    final cleanId = rawName.replaceAll('/', '-').replaceAll(RegExp(r'\s+'), '').toUpperCase();

    // Check if an active room with this exact name already exists
    try {
      final existing = await ref.read(roomRepositoryProvider).getRoom(cleanId);
      if (existing != null && 
          existing.status == RoomStatus.active && 
          !DateTime.now().isAfter(existing.expiresAt)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A room with this name is already active! Choose another name or join it.'),
              backgroundColor: Colors.orangeAccent,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    } catch (_) {}

    final now = DateTime.now();
    final room = Room(
      id: cleanId,
      name: rawName,
      createdAt: now,
      expiresAt: now.add(Duration(minutes: _expiryMinutes)),
    );

    final success = await ref.read(currentRoomProvider.notifier).createAndJoinRoom(room);
    if (success && mounted) {
      Clipboard.setData(ClipboardData(text: rawName));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room "$rawName" created! Name copied to clipboard.'),
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
                  hintText: 'e.g. SecretNest',
                  helperText: 'No separate code needed! Partner enters this same name to join.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.meeting_room, color: AppTheme.primaryNeon),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Room Expiry', style: Theme.of(context).textTheme.titleMedium),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNeon.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryNeon.withOpacity(0.4)),
                    ),
                    child: Text(
                      _formatDuration(_expiryMinutes),
                      style: const TextStyle(
                        color: AppTheme.primaryNeon,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [15, 30, 60, 120].map((mins) {
                  final isSelected = _expiryMinutes == mins;
                  return ChoiceChip(
                    label: Text(
                      mins == 120 ? '2 Hours (Default)' : _formatDuration(mins),
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryNeon,
                    backgroundColor: Colors.white10,
                    showCheckmark: false,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _expiryMinutes = mins;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Slider(
                value: _expiryMinutes.toDouble(),
                min: 5,
                max: 120, // 2 hours
                divisions: 23, // 5 min intervals: 5, 10, 15, ..., 120
                activeColor: AppTheme.primaryNeon,
                inactiveColor: Colors.white24,
                label: _formatDuration(_expiryMinutes),
                onChanged: (val) {
                  setState(() {
                    _expiryMinutes = (val / 5).round() * 5;
                  });
                },
              ),
              Text(
                'Room self-destructs in ${_formatDuration(_expiryMinutes)} (Step: 5 min intervals)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.secondaryNeon, fontSize: 13),
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
