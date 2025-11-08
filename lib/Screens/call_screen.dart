import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallScreen extends StatefulWidget {
  final String callerId;
  final String calleeId;
  final String calleeName;
  final bool isIncoming;
  final String? callId;

  const CallScreen({
    super.key, 
    required this.callerId, 
    required this.calleeId, 
    required this.calleeName,
    this.isIncoming = false,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _remoteDescSet = false;

  // Call document id
  String? _callDocId;
  StreamSubscription? _callSub;
  StreamSubscription? _callerCandidatesSub;
  StreamSubscription? _calleeCandidatesSub;

  bool _inCalling = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _startCall();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startCall() async {
    // Get user media
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      }
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;

      // Create peer connection
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      };
      _peerConnection = await createPeerConnection(configuration);

      // Add local tracks
      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      // Remote stream
      _peerConnection?.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams[0];
        }
      };

      // ICE candidate handling
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) async {
        if (candidate.candidate == null) return;
        final candidateCollection = widget.isIncoming ? 'calleeCandidates' : 'callerCandidates';
        if (_callDocId != null) {
          final col = _firestore.collection('calls').doc(_callDocId).collection(candidateCollection);
          await col.add({
            'candidate': candidate.candidate,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'sdpMid': candidate.sdpMid,
          });
        }
      };

      _callDocId = widget.isIncoming ? widget.callId : _firestore.collection('calls').doc().id;

      // Set up connection state handling
      _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('Connection state changed: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _hangUp();
        }
      };

      if (widget.isIncoming) {
        await _handleIncomingCall();
      } else {
        await _makeOutgoingCall();
      }

    } catch (e) {
      debugPrint('startCall error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call start failed: $e')));
      }
      _hangUp();
    }
  }

  Future<void> _handleIncomingCall() async {
    try {
      final callDoc = _firestore.collection('calls').doc(_callDocId);
      final callData = await callDoc.get();
      
      if (!callData.exists) {
        throw Exception('Call no longer exists');
      }

      final data = callData.data()!;
      final offer = data['offer'];
      if (offer == null) throw Exception('No offer in call');

      // Set remote description (caller's offer)
      final rtcOffer = RTCSessionDescription(offer['sdp'], offer['type']);
      await _peerConnection!.setRemoteDescription(rtcOffer);

      // Create and set local description (answer)
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer
      await callDoc.update({
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        },
        'state': 'answered',
      });

      // Listen for caller ICE candidates
      _callerCandidatesSub = callDoc.collection('callerCandidates').snapshots().listen((snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data == null) continue;
            _peerConnection!.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
          }
        }
      });

      // Listen for call state changes
      _callSub = callDoc.snapshots().listen((snapshot) {
        if (!snapshot.exists) {
          _hangUp();
          return;
        }
        final data = snapshot.data()!;
        if (data['state'] == 'ended' || data['state'] == 'rejected') {
          _hangUp();
          return;
        }
        if (!_inCalling && data['state'] == 'answered') {
          setState(() {
            _inCalling = true;
          });
        }
      });

      setState(() {
        _inCalling = true;
      });

    } catch (e) {
      debugPrint('Error handling incoming call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to answer call: $e')),
      );
      _hangUp();
    }
  }

  Future<void> _makeOutgoingCall() async {
    try {
      final callDoc = _firestore.collection('calls').doc(_callDocId);

      // Start call timeout
      _startCallTimeout();

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Save offer to call doc
      await callDoc.set({
        'callerId': widget.callerId,
        'calleeId': widget.calleeId,
        'callerName': 'caller',
        'calleeName': widget.calleeName,
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'state': 'offer',
      });

      // Listen for answer
      _callSub = callDoc.snapshots().listen((snapshot) async {
        if (!snapshot.exists) {
          _hangUp();
          return;
        }

        final data = snapshot.data();
        if (data == null) return;

        if (data['state'] == 'ended' || data['state'] == 'rejected') {
          _hangUp();
          return;
        }

        if (data['answer'] != null && !_remoteDescSet) {
          final answer = data['answer'];
          final rtcAnswer = RTCSessionDescription(answer['sdp'], answer['type']);
          try {
            await _peerConnection?.setRemoteDescription(rtcAnswer);
            _remoteDescSet = true;
            setState(() {
              _inCalling = true;
            });
          } catch (e) {
            debugPrint('setRemoteDescription error: $e');
          }
        }
      });

      // Listen for callee ICE candidates
      _calleeCandidatesSub = callDoc.collection('calleeCandidates').snapshots().listen((snap) {
        for (final doc in snap.docChanges) {
          if (doc.type == DocumentChangeType.added) {
            final data = doc.doc.data();
            if (data == null) continue;
            _peerConnection?.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
          }
        }
      });

    } catch (e) {
      debugPrint('Error making outgoing call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to make call: $e')),
        );
      }
      _hangUp();
    }
  }

  // Add timeout for unanswered calls
  Future<void> _startCallTimeout() async {
    await Future.delayed(const Duration(seconds: 30));
    if (!_inCalling && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call was not answered')),
      );
      _hangUp();
    }
  }

  Future<void> _hangUp() async {
    try {
      if (_callDocId != null) {
        final callRef = _firestore.collection('calls').doc(_callDocId);
        // update state
        await callRef.update({'state': 'ended'});
        // cleanup subcollections
        final callerCols = await callRef.collection('callerCandidates').get();
        for (final d in callerCols.docs) {
          await d.reference.delete();
        }
        final calleeCols = await callRef.collection('calleeCandidates').get();
        for (final d in calleeCols.docs) {
          await d.reference.delete();
        }
        await callRef.delete();
      }
    } catch (e) {
      debugPrint('hangup cleanup error: $e');
    }

    _peerConnection?.close();
    _localStream?.dispose();
    _remoteRenderer.srcObject = null;
    _localRenderer.srcObject = null;

    _callSub?.cancel();
    _callerCandidatesSub?.cancel();
    _calleeCandidatesSub?.cancel();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hangUp();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callStatus = widget.isIncoming ? 
      (_inCalling ? 'Connected' : 'Answering call from ${widget.calleeName}...') :
      (_inCalling ? 'Connected' : 'Calling ${widget.calleeName}...');

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            // Call status bar
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black54,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _hangUp,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.calleeName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          callStatus,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Video views
            Expanded(
              child: Stack(
                children: [
                  // Remote video (full screen)
                  _inCalling
                      ? RTCVideoView(
                          _remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                  // Local video (picture-in-picture)
                  Positioned(
                    right: 20,
                    top: 20,
                    width: 120,
                    height: 180,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Call controls
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              color: Colors.black54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                    color: _isMuted ? Colors.red : Colors.white,
                    onPressed: () {
                      if (_localStream != null) {
                        final audioTrack = _localStream!.getAudioTracks().first;
                        audioTrack.enabled = !audioTrack.enabled;
                        setState(() => _isMuted = !audioTrack.enabled);
                      }
                    },
                  ),
                  FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: _hangUp,
                    child: const Icon(Icons.call_end),
                  ),
                  IconButton(
                    icon: Icon(_isCameraOff ? Icons.videocam_off : Icons.videocam),
                    color: _isCameraOff ? Colors.red : Colors.white,
                    onPressed: () {
                      if (_localStream != null) {
                        final videoTrack = _localStream!.getVideoTracks().first;
                        videoTrack.enabled = !videoTrack.enabled;
                        setState(() => _isCameraOff = !videoTrack.enabled);
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(_isSpeakerOn ? Icons.volume_up : Icons.volume_down),
                    color: Colors.white,
                    onPressed: () {
                      // Note: In a real app, you'd want to use platform-specific code
                      // to handle audio routing. This is just for UI demonstration.
                      setState(() => _isSpeakerOn = !_isSpeakerOn);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
