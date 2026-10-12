import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class ChatMediaService {
  final ImagePicker _picker = ImagePicker();
  AudioRecorder? _audioRecorder;
  String? _currentRecordingPath;
  DateTime? _recordStartTime;

  /// Picks and compresses an image from camera or gallery into base64
  Future<String?> pickImage({required ImageSource source}) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 65, // Generates clean ~30-50KB image
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  /// Checks microphone permission and starts audio recording
  Future<bool> startVoiceRecording() async {
    try {
      _audioRecorder ??= AudioRecorder();
      if (!await _audioRecorder!.hasPermission()) {
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = filePath;
      _recordStartTime = DateTime.now();

      await _audioRecorder!.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: filePath,
      );
      return true;
    } catch (e) {
      debugPrint('Error starting voice recording: $e');
      return false;
    }
  }

  /// Stops audio recording and returns base64 string and duration in seconds
  Future<({String base64Audio, int durationSeconds})?> stopVoiceRecording() async {
    try {
      if (_audioRecorder == null) return null;
      final path = await _audioRecorder!.stop();
      final duration = _recordStartTime != null
          ? DateTime.now().difference(_recordStartTime!).inSeconds
          : 1;

      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      // Clean up local temp recording file
      try {
        await file.delete();
      } catch (_) {}

      final base64Audio = base64Encode(bytes);
      return (base64Audio: base64Audio, durationSeconds: duration > 0 ? duration : 1);
    } catch (e) {
      debugPrint('Error stopping voice recording: $e');
      return null;
    }
  }

  /// Cancel current recording without saving
  Future<void> cancelVoiceRecording() async {
    try {
      if (_audioRecorder != null && await _audioRecorder!.isRecording()) {
        await _audioRecorder!.stop();
      }
      if (_currentRecordingPath != null) {
        final f = File(_currentRecordingPath!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  void dispose() {
    _audioRecorder?.dispose();
    _audioRecorder = null;
  }
}
