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

  final List<RTCIceCandidate> _remoteCandidatesQueue = [];
  bool _isRemoteDescriptionSet = false;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

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

  Future<void> _cleanCandidateCollection(CollectionReference ref) async {
    try {
      final snapshot = await ref.get();
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Error cleaning candidate collection: $e');
    }
  }

  Future<void> _addOrQueueCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) return;
    if (!_isRemoteDescriptionSet) {
      debugPrint('Queueing ICE candidate until remote description is set: ${candidate.sdpMid}');
      _remoteCandidatesQueue.add(candidate);
      return;
    }
    try {
      await _peerConnection!.addCandidate(candidate);
      debugPrint('Added ICE candidate directly: ${candidate.sdpMid}');
    } catch (e) {
      debugPrint('Error adding ICE candidate: $e');
    }
  }

  Future<void> _processQueuedCandidates() async {
    if (_peerConnection == null) return;
    if (_remoteCandidatesQueue.isEmpty) return;
    debugPrint('Flushing ${_remoteCandidatesQueue.length} queued ICE candidates');
    final queue = List<RTCIceCandidate>.from(_remoteCandidatesQueue);
    _remoteCandidatesQueue.clear();
    for (final candidate in queue) {
      try {
        await _peerConnection!.addCandidate(candidate);
        debugPrint('Added queued ICE candidate: ${candidate.sdpMid}');
      } catch (e) {
        debugPrint('Error adding queued ICE candidate: $e');
      }
    }
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

      try {
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (e) {
        if (!isAudioOnly) {
          debugPrint('getUserMedia with facingMode constraint failed, retrying simple video: $e');
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': true,
          });
        } else {
          rethrow;
        }
      }

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
        {'urls': 'stun:stun3.l.google.com:19302'},
        {'urls': 'stun:stun4.l.google.com:19302'},
        {'urls': 'stun:stun.services.mozilla.com'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('WebRTC ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _setStatus(CallStatus.connected);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        debugPrint('WebRTC ICE connection failed!');
      }
    };

    _peerConnection?.onAddStream = (MediaStream stream) {
      debugPrint('WebRTC onAddStream: id=${stream.id}, audioTracks=${stream.getAudioTracks().length}, videoTracks=${stream.getVideoTracks().length}');
      if (stream.id != _localStream?.id) {
        _remoteStream = stream;
        _setStatus(CallStatus.connected);
        onAddRemoteStream?.call(stream);
      }
    };

    _peerConnection?.onTrack = (RTCTrackEvent event) async {
      debugPrint('WebRTC onTrack: track.kind=${event.track.kind}, streams=${event.streams.length}');
      if (event.streams.isNotEmpty && event.streams[0].id != _localStream?.id) {
        _remoteStream = event.streams[0];
      } else {
        if (_remoteStream == null) {
          _remoteStream = await createLocalMediaStream('remote_stream_${DateTime.now().millisecondsSinceEpoch}');
        }
        if (!_remoteStream!.getTracks().any((t) => t.id == event.track.id)) {
          _remoteStream!.addTrack(event.track);
        }
      }
      _setStatus(CallStatus.connected);
      if (_remoteStream != null) {
        onAddRemoteStream?.call(_remoteStream!);
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
          debugPrint('Error adding ICE candidate to Firestore: $e');
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
    _isRemoteDescriptionSet = false;
    _remoteCandidatesQueue.clear();

    // Clean up previous call candidates from Firestore
    await _cleanCandidateCollection(sessionRef.collection('callerCandidates'));
    await _cleanCandidateCollection(sessionRef.collection('calleeCandidates'));

    await _createPeerConnection(true);

    final offer = await _peerConnection!.createOffer(<String, dynamic>{
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': !isAudioOnly,
      },
      'optional': [],
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
          _isRemoteDescriptionSet = true;
          await _processQueuedCandidates();
          _setStatus(CallStatus.connected);
        }
      } else if (data != null && data['status'] == 'rejected') {
        _setStatus(CallStatus.rejected);
      } else if (data != null && data['status'] == 'ended') {
        _setStatus(CallStatus.ended);
      }
    });

    _candidatesSubscription?.cancel();
    _candidatesSubscription = sessionRef.collection('calleeCandidates').snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['candidate'] != null) {
            final candidate = RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            );
            await _addOrQueueCandidate(candidate);
          }
        }
      }
    });
  }

  Future<void> _joinCall(DocumentReference sessionRef, Map<String, dynamic> data) async {
    _isRemoteDescriptionSet = false;
    _remoteCandidatesQueue.clear();

    await _createPeerConnection(false);

    final offer = data['offer'];
    final remoteOfferDesc = RTCSessionDescription(offer['sdp'], offer['type']);
    await _peerConnection!.setRemoteDescription(remoteOfferDesc);
    _isRemoteDescriptionSet = true;
    await _processQueuedCandidates();

    final answer = await _peerConnection!.createAnswer(<String, dynamic>{
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': !isAudioOnly,
      },
      'optional': [],
    });
    await _peerConnection!.setLocalDescription(answer);

    await sessionRef.update({
      'status': 'connected',
      'answer': answer.toMap(),
    });
    _setStatus(CallStatus.connected);

    _candidatesSubscription?.cancel();
    _candidatesSubscription = sessionRef.collection('callerCandidates').snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final candidateData = change.doc.data();
          if (candidateData != null && candidateData['candidate'] != null) {
            final candidate = RTCIceCandidate(
              candidateData['candidate'],
              candidateData['sdpMid'],
              candidateData['sdpMLineIndex'],
            );
            await _addOrQueueCandidate(candidate);
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

  Future<void> toggleSpeaker(bool enabled) async {
    try {
      await Helper.setSpeakerphoneOn(enabled);
      debugPrint('Speakerphone set to: $enabled');
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

    _remoteCandidatesQueue.clear();
    _isRemoteDescriptionSet = false;

    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}

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
