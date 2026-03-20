import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../room/providers/room_provider.dart';

final webRTCProvider = Provider.autoDispose<WebRTCRepository>((ref) {
  final repo = WebRTCRepository(ref.watch(firestoreProvider));
  ref.onDispose(() => repo.dispose());
  return repo;
});

class WebRTCRepository {
  final FirebaseFirestore _firestore;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _roomId;
  Function(MediaStream stream)? onAddRemoteStream;
  Function(MediaStream stream)? onAddLocalStream;

  WebRTCRepository(this._firestore);

  Future<void> initLocalStream() async {
    final mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640', 
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (onAddLocalStream != null) {
      onAddLocalStream!(_localStream!);
    }
  }

  Future<void> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };
    _peerConnection = await createPeerConnection(configuration);

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (_roomId != null) {
        _firestore.collection('rooms').doc(_roomId).collection('callerCandidates').add(candidate.toMap());
      }
    };

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && event.streams[0].id != _localStream?.id) {
        _remoteStream = event.streams[0];
        if (onAddRemoteStream != null) {
          onAddRemoteStream!(_remoteStream!);
        }
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });
  }

  Future<void> startCall(String roomId) async {
    _roomId = roomId;
    await _createPeerConnection();

    final roomRef = _firestore.collection('rooms').doc(roomId);

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await roomRef.update({'offer': offer.toMap()});

    roomRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data != null && data.containsKey('answer')) {
        final remoteDesc = await _peerConnection?.getRemoteDescription();
        if (remoteDesc == null) {
          final answer = RTCSessionDescription(
            data['answer']['sdp'],
            data['answer']['type'],
          );
          await _peerConnection?.setRemoteDescription(answer);
        }
      }
    });

    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          _peerConnection!.addCandidate(
            RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
          );
        }
      }
    });
  }

  Future<void> joinCall(String roomId) async {
    _roomId = roomId;
    await _createPeerConnection();

    final roomRef = _firestore.collection('rooms').doc(roomId);
    final roomSnapshot = await roomRef.get();
    
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      roomRef.collection('calleeCandidates').add(candidate.toMap());
    };

    if (roomSnapshot.exists) {
      final data = roomSnapshot.data();
      if (data != null && data.containsKey('offer')) {
        final offer = data['offer'];
        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']),
        );

        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

        await roomRef.update({'answer': answer.toMap()});

        roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data()!;
              _peerConnection!.addCandidate(
                RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
              );
            }
          }
        });
      }
    }
  }

  void toggleAudio(bool enabled) {
    if (_localStream != null) {
      _localStream!.getAudioTracks()[0].enabled = enabled;
    }
  }

  void toggleVideo(bool enabled) {
    if (_localStream != null) {
      _localStream!.getVideoTracks()[0].enabled = enabled;
    }
  }

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  Future<void> dispose() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.close();
  }
}
