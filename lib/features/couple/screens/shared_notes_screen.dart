import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../room/providers/room_provider.dart';
import '../../../core/theme/app_theme.dart';

class SharedNotesScreen extends ConsumerStatefulWidget {
  const SharedNotesScreen({super.key});

  @override
  ConsumerState<SharedNotesScreen> createState() => _SharedNotesScreenState();
}

class _SharedNotesScreenState extends ConsumerState<SharedNotesScreen> {
  final _noteController = TextEditingController();
  
  void _saveNote(String roomId, String currentNotes) {
    FirebaseFirestore.instance
      .collection('rooms')
      .doc(roomId)
      .collection('extras')
      .doc('notes')
      .set({'content': _noteController.text});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note Saved!')));
  }

  @override
  Widget build(BuildContext context) {
    final roomId = ref.read(currentRoomProvider).value?.id;
    if (roomId == null) return const Scaffold(body: Center(child: Text('No active room')));

    final notesStream = FirebaseFirestore.instance
      .collection('rooms')
      .doc(roomId)
      .collection('extras')
      .doc('notes')
      .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Our Secret Notes')),
      body: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.backgroundDark, AppTheme.backgroundLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: StreamBuilder<DocumentSnapshot>(
          stream: notesStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.data() as Map<String, dynamic>?;
            final content = data?['content'] as String? ?? '';

            if (_noteController.text.isEmpty && content.isNotEmpty) {
              _noteController.text = content;
            }

            return Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      hintText: 'Write something private together...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save to Shared Vault'),
                  onPressed: () => _saveNote(roomId, content),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
