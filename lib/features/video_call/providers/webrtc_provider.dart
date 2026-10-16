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
      debugPrint('Queueing ICE candidate until remote description is set: mid=${candidate.sdpMid}');
      _remoteCandidatesQueue.add(candidate);
      return;
    }
    try {
      await _peerConnection!.addCandidate(candidate);
      debugPrint('Added ICE candidate directly: mid=${candidate.sdpMid}');
    } catch (e) {
      debugPrint('Error adding ICE candidate: $e');
    }
  }

  Future<void> _processQueuedCandidates() async {
    if (_peerConnection == null || _remoteCandidatesQueue.isEmpty) return;
    debugPrint('Flushing ${_remoteCandidatesQueue.length} queued ICE candidates');
    final queue = List<RTCIceCandidate>.from(_remoteCandidatesQueue);
    _remoteCandidatesQueue.clear();
    for (final candidate in queue) {
      try {
        await _peerConnection!.addCandidate(candidate);
        debugPrint('Added queued ICE candidate: mid=${candidate.sdpMid}');
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
        debugPrint('getUserMedia with facingMode constraint failed, retrying simple getUserMedia: $e');
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': !isAudioOnly,
        });
      }

      unmuteAllTracks();

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

  Future<void> _createPeerConnection(bool isCaller, DocumentReference sessionRef) async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
        {'urls': 'stun:stun4.l.google.com:19302'},
        {'urls': 'stun:stun.cloudflare.com:3478'},
        {'urls': 'stun:stun.services.mozilla.com'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('WebRTC ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        unmuteAllTracks();
        _setStatus(CallStatus.connected);
        toggleSpeaker(true);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        debugPrint('WebRTC ICE connection failed!');
        _setStatus(CallStatus.error);
      }
    };

    _peerConnection?.onAddStream = (MediaStream stream) {
      debugPrint('WebRTC onAddStream: id=${stream.id}, audio=${stream.getAudioTracks().length}, video=${stream.getVideoTracks().length}');
      if (stream.id != _localStream?.id) {
        _remoteStream = stream;
        unmuteAllTracks();
        _setStatus(CallStatus.connected);
        onAddRemoteStream?.call(stream);
      }
    };

    _peerConnection?.onTrack = (RTCTrackEvent event) async {
      debugPrint('WebRTC onTrack: kind=${event.track.kind}, id=${event.track.id}, streams=${event.streams.length}');
      event.track.enabled = true;
      if (event.streams.isNotEmpty && event.streams[0].id != _localStream?.id) {
        _remoteStream = event.streams[0];
      } else {
        _remoteStream ??= await createLocalMediaStream('remote_stream');
        if (!_remoteStream!.getTracks().any((t) => t.id == event.track.id)) {
          _remoteStream!.addTrack(event.track);
        }
      }
      unmuteAllTracks();
      if (_remoteStream != null) {
        _setStatus(CallStatus.connected);
        onAddRemoteStream?.call(_remoteStream!);
      }
    };

    _localStream?.getTracks().forEach((track) {
      track.enabled = true;
      _peerConnection?.addTrack(track, _localStream!);
    });

    final targetCol = isCaller
        ? sessionRef.collection('callerCandidates')
        : sessionRef.collection('calleeCandidates');

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (_roomId != null && _firestore != null && candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        final candidateData = candidate.toMap();
        candidateData['createdAt'] = FieldValue.serverTimestamp();

        targetCol.add(candidateData).catchError((e) {
          debugPrint('Error adding ICE candidate to Firestore: $e');
        });
      }
    };
  }

  void _listenForCandidates(CollectionReference candidateCol) {
    _candidatesSubscription?.cancel();
    _candidatesSubscription = candidateCol.snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          final candidateStr = data['candidate'] as String?;
          if (candidateStr == null || candidateStr.trim().isEmpty) continue;

          final sdpMid = data['sdpMid'] as String?;
          final rawIndex = data['sdpMLineIndex'];
          final int? sdpMLineIndex = rawIndex is num
              ? rawIndex.toInt()
              : (rawIndex != null ? int.tryParse(rawIndex.toString()) : null);

          if (sdpMid == null && sdpMLineIndex == null) continue;

          final candidate = RTCIceCandidate(candidateStr, sdpMid, sdpMLineIndex);
          await _addOrQueueCandidate(candidate);
        }
      }
    });
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
      
      DocumentSnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await sessionRef.get(const GetOptions(source: Source.server));
      } catch (_) {
        snapshot = await sessionRef.get();
      }
      final data = snapshot.data();

      bool isExistingCall = false;
      if (data != null && data['callerId'] != userId && data['offer'] != null) {
        final status = data['status'];
        // ONLY join if the call is actively ringing/calling
        if (status == 'calling') {
          final createdAt = data['createdAt'];
          if (createdAt is Timestamp) {
            final age = DateTime.now().difference(createdAt.toDate());
            if (age.inSeconds.abs() < 120) {
              isExistingCall = true;
            }
          } else {
            isExistingCall = true;
          }
        }
      }

      if (isExistingCall) {
        debugPrint('Joining existing call as callee for room: $cleanRoomId ($_sessionDocName)...');
        await _joinCall(sessionRef, data!);
      } else {
        debugPrint('Starting new call as caller for room: $cleanRoomId ($_sessionDocName)...');
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

    // Clean old candidate collections BEFORE starting peer connection to avoid deleting new candidates
    await _cleanCandidateCollection(sessionRef.collection('callerCandidates'));
    await _cleanCandidateCollection(sessionRef.collection('calleeCandidates'));

    await _createPeerConnection(true, sessionRef);

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

    _listenForCandidates(sessionRef.collection('calleeCandidates'));

    _sessionSubscription?.cancel();
    _sessionSubscription = sessionRef.snapshots().listen((snapshot) async {
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data != null && data['status'] == 'connected' && data['answer'] != null) {
        if (!_isRemoteDescriptionSet && _peerConnection != null) {
          final answer = RTCSessionDescription(
            data['answer']['sdp'],
            data['answer']['type'],
          );
          await _peerConnection!.setRemoteDescription(answer);
          _isRemoteDescriptionSet = true;
          await _processQueuedCandidates();
          _setStatus(CallStatus.connected);
          unmuteAllTracks();
          await toggleSpeaker(true);
        }
      } else if (data != null && data['status'] == 'rejected') {
        _setStatus(CallStatus.rejected);
      } else if (data != null && data['status'] == 'ended') {
        _setStatus(CallStatus.ended);
      }
    });
  }

  Future<void> _joinCall(DocumentReference sessionRef, Map<String, dynamic> data) async {
    _isRemoteDescriptionSet = false;
    _remoteCandidatesQueue.clear();

    await _createPeerConnection(false, sessionRef);

    _listenForCandidates(sessionRef.collection('callerCandidates'));

    final offer = data['offer'];
    final remoteOfferDesc = RTCSessionDescription(offer['sdp'], offer['type']);
    await _peerConnection!.setRemoteDescription(remoteOfferDesc);

    final answer = await _peerConnection!.createAnswer(<String, dynamic>{
      'offerToReceiveVideo': isAudioOnly ? 0 : 1,
      'offerToReceiveAudio': 1,
    });
    await _peerConnection!.setLocalDescription(answer);

    _isRemoteDescriptionSet = true;
    await _processQueuedCandidates();

    await sessionRef.set({
      'status': 'connected',
      'answer': answer.toMap(),
    }, SetOptions(merge: true));
    _setStatus(CallStatus.connected);
    unmuteAllTracks();
    await toggleSpeaker(true);

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

  void unmuteAllTracks() {
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.enabled = true;
      }
    }
    if (_remoteStream != null) {
      for (final track in _remoteStream!.getTracks()) {
        track.enabled = true;
      }
    }
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
        final sessionRef = _firestore
            .collection('rooms')
            .doc(cleanRoomId)
            .collection('call')
            .doc(_sessionDocName);
        await sessionRef.set({
          'status': 'rejected',
          'endedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _cleanCandidateCollection(sessionRef.collection('callerCandidates'));
        await _cleanCandidateCollection(sessionRef.collection('calleeCandidates'));
      } catch (e) {
        debugPrint('Error rejecting call in Firestore: $e');
      }
    }
  }

  Future<void> endCall(String? roomId) async {
    if (roomId != null && _firestore != null) {
      final cleanRoomId = roomId.trim().toUpperCase();
      try {
        final sessionRef = _firestore
            .collection('rooms')
            .doc(cleanRoomId)
            .collection('call')
            .doc(_sessionDocName);
        await sessionRef.set({
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _cleanCandidateCollection(sessionRef.collection('callerCandidates'));
        await _cleanCandidateCollection(sessionRef.collection('calleeCandidates'));
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
  final cleanRoomId = roomId.trim().toUpperCase();
  return FirebaseFirestore.instance
      .collection('rooms')
      .doc(cleanRoomId)
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
  final cleanRoomId = roomId.trim().toUpperCase();
  return FirebaseFirestore.instance
      .collection('rooms')
      .doc(cleanRoomId)
      .collection('call')
      .doc('audio_session')
      .snapshots()
      .map((snap) => snap.data());
});
