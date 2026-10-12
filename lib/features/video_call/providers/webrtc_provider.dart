import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../room/providers/room_provider.dart';

enum CallStatus { idle, calling, connected, ended, rejected, error }

class WebRTCRepository {
  final FirebaseFirestore? _firestore;
  final bool isAudioOnly;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _roomId;
  String? _userId;

  String get _sessionDocName => isAudioOnly ? 'audio_session' : 'session';

  StreamSubscription? _sessionSubscription;
  StreamSubscription? _candidatesSubscription;

  Function(MediaStream stream)? onAddRemoteStream;
  Function(MediaStream stream)? onAddLocalStream;
  Function(CallStatus status)? onCallStatusChanged;
  Function(String error)? onError;

  CallStatus status = CallStatus.idle;

  WebRTCRepository(this._firestore, {this.isAudioOnly = false});

  void _setStatus(CallStatus newStatus) {
    status = newStatus;
    onCallStatusChanged?.call(newStatus);
  }

  Future<bool> initLocalStream() async {
    try {
      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': isAudioOnly
            ? false
            : {
                'facingMode': 'user',
                'optional': [],
              },
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      if (onAddLocalStream != null && _localStream != null) {
        onAddLocalStream!(_localStream!);
      }
      return true;
    } catch (e, st) {
      debugPrint('Error getting user media: $e\n$st');
      onError?.call('Could not access ${isAudioOnly ? "microphone" : "camera/mic"}: $e');
      _setStatus(CallStatus.error);
      return false;
    }
  }

  Future<void> _createPeerConnection(bool isCaller) async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && event.streams[0].id != _localStream?.id) {
        _remoteStream = event.streams[0];
        _setStatus(CallStatus.connected);
        if (onAddRemoteStream != null) {
          onAddRemoteStream!(_remoteStream!);
        }
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    final targetCandidateCollection = isCaller ? 'callerCandidates' : 'calleeCandidates';
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (_roomId != null && _firestore != null && candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        _firestore
            .collection('rooms')
            .doc(_roomId)
            .collection('call')
            .doc(_sessionDocName)
            .collection(targetCandidateCollection)
            .add(candidate.toMap())
            .catchError((e) {
          debugPrint('Error adding ICE candidate: $e');
        });
      }
    };
  }

  Future<void> startOrJoinCall(String roomId, String userId) async {
    final cleanRoomId = roomId.trim().toUpperCase();
    _roomId = cleanRoomId;
    _userId = userId;

    if (_firestore == null) {
      _setStatus(CallStatus.connected);
      return;
    }

    try {
      final sessionRef = _firestore.collection('rooms').doc(cleanRoomId).collection('call').doc(_sessionDocName);
      final snapshot = await sessionRef.get();
      final data = snapshot.data();

      final bool isExistingCall = data != null &&
          data['status'] == 'calling' &&
          data['callerId'] != userId &&
          data['offer'] != null;

      if (isExistingCall) {
        debugPrint('Joining existing call as callee...');
        await _joinCall(sessionRef, data);
      } else {
        debugPrint('Starting new call as caller...');
        await _startCall(sessionRef);
      }
    } catch (e, st) {
      debugPrint('Error starting or joining call: $e\n$st');
      onError?.call('Call failed: $e');
      _setStatus(CallStatus.error);
    }
  }

  Future<void> _startCall(DocumentReference sessionRef) async {
    _setStatus(CallStatus.calling);
    await _createPeerConnection(true);

    final offer = await _peerConnection!.createOffer(<String, dynamic>{
      'offerToReceiveVideo': isAudioOnly ? 0 : 1,
      'offerToReceiveAudio': 1,
    });
    await _peerConnection!.setLocalDescription(offer);

    await sessionRef.set({
      'callerId': _userId,
      'status': 'calling',
      'callType': isAudioOnly ? 'audio' : 'video',
      'offer': offer.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    _sessionSubscription?.cancel();
    _sessionSubscription = sessionRef.snapshots().listen((snapshot) async {
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data != null && data['status'] == 'connected' && data['answer'] != null) {
        final currentRemoteDesc = await _peerConnection?.getRemoteDescription();
        if (currentRemoteDesc == null) {
          final answer = RTCSessionDescription(
            data['answer']['sdp'],
            data['answer']['type'],
          );
          await _peerConnection?.setRemoteDescription(answer);
          _setStatus(CallStatus.connected);
        }
      } else if (data != null && data['status'] == 'rejected') {
        _setStatus(CallStatus.rejected);
      } else if (data != null && data['status'] == 'ended') {
        _setStatus(CallStatus.ended);
      }
    });

    _candidatesSubscription?.cancel();
    _candidatesSubscription = sessionRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['candidate'] != null) {
            _peerConnection?.addCandidate(
              RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
            );
          }
        }
      }
    });
  }

  Future<void> _joinCall(DocumentReference sessionRef, Map<String, dynamic> data) async {
    await _createPeerConnection(false);

    final offer = data['offer'];
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await _peerConnection!.createAnswer(<String, dynamic>{
      'offerToReceiveVideo': isAudioOnly ? 0 : 1,
      'offerToReceiveAudio': 1,
    });
    await _peerConnection!.setLocalDescription(answer);

    await sessionRef.update({
      'status': 'connected',
      'answer': answer.toMap(),
    });
    _setStatus(CallStatus.connected);

    _candidatesSubscription?.cancel();
    _candidatesSubscription = sessionRef.collection('callerCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['candidate'] != null) {
            _peerConnection?.addCandidate(
              RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
            );
          }
        }
      }
    });

    _sessionSubscription?.cancel();
    _sessionSubscription = sessionRef.snapshots().listen((snapshot) {
      final sessionData = snapshot.data() as Map<String, dynamic>?;
      if (sessionData != null && sessionData['status'] == 'rejected') {
        _setStatus(CallStatus.rejected);
      } else if (sessionData != null && sessionData['status'] == 'ended') {
        _setStatus(CallStatus.ended);
      }
    });
  }

  void toggleAudio(bool enabled) {
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = enabled;
      }
    }
  }

  void toggleVideo(bool enabled) {
    if (_localStream != null) {
      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = enabled;
      }
    }
  }

  void switchCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void toggleSpeaker(bool enabled) {
    try {
      Helper.setSpeakerphoneOn(enabled);
    } catch (e) {
      debugPrint('Error toggling speakerphone: $e');
    }
  }

  Future<void> rejectCall(String? roomId) async {
    if (roomId != null && _firestore != null) {
      final cleanRoomId = roomId.trim().toUpperCase();
      try {
        await _firestore
            .collection('rooms')
            .doc(cleanRoomId)
            .collection('call')
            .doc(_sessionDocName)
            .set({
              'status': 'rejected',
              'endedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error rejecting call in Firestore: $e');
      }
    }
  }

  Future<void> endCall(String? roomId) async {
    if (roomId != null && _firestore != null) {
      final cleanRoomId = roomId.trim().toUpperCase();
      try {
        await _firestore
            .collection('rooms')
            .doc(cleanRoomId)
            .collection('call')
            .doc(_sessionDocName)
            .set({
              'status': 'ended',
              'endedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error setting call ended in Firestore: $e');
      }
    }
    _setStatus(CallStatus.ended);
    await dispose();
  }

  Future<void> dispose() async {
    _sessionSubscription?.cancel();
    _candidatesSubscription?.cancel();
    _sessionSubscription = null;
    _candidatesSubscription = null;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    if (_remoteStream != null) {
      await _remoteStream!.dispose();
      _remoteStream = null;
    }

    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }
  }
}

final webRTCProvider = Provider.autoDispose<WebRTCRepository>((ref) {
  final firestore = Firebase.apps.isNotEmpty ? ref.watch(firestoreProvider) : null;
  final repo = WebRTCRepository(firestore, isAudioOnly: false);
  ref.onDispose(() => repo.dispose());
  return repo;
});

final audioWebRTCProvider = Provider.autoDispose<WebRTCRepository>((ref) {
  final firestore = Firebase.apps.isNotEmpty ? ref.watch(firestoreProvider) : null;
  final repo = WebRTCRepository(firestore, isAudioOnly: true);
  ref.onDispose(() => repo.dispose());
  return repo;
});

final callSessionStreamProvider =
    StreamProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, roomId) {
  if (Firebase.apps.isEmpty) {
    return Stream.value(null);
  }
  return FirebaseFirestore.instance
      .collection('rooms')
      .doc(roomId)
      .collection('call')
      .doc('session')
      .snapshots()
      .map((snap) => snap.data());
});

final audioCallSessionStreamProvider =
    StreamProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, roomId) {
  if (Firebase.apps.isEmpty) {
    return Stream.value(null);
  }
  return FirebaseFirestore.instance
      .collection('rooms')
      .doc(roomId)
      .collection('call')
      .doc('audio_session')
      .snapshots()
      .map((snap) => snap.data());
});
