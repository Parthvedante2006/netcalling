import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

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
  bool _isSpeakerOn = false;
  
  DateTime? _callStartTime;
  Timer? _durationTimer;
  String _callDuration = '00:00';

  Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _startCall();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required for calls')),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to request microphone permission')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _startCall() async {
    // Request microphone permission first
    final hasPermission = await _requestMicrophonePermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    try {
      // Get user media - audio only for voice calls
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      // Verify audio tracks
      final audioTracks = _localStream?.getAudioTracks();
      debugPrint('Audio tracks: ${audioTracks?.length}');
      if (audioTracks?.isEmpty ?? true) {
        throw Exception('No audio track available');
      }
      debugPrint('Audio track enabled: ${audioTracks!.first.enabled}');

      // Create peer connection with audio configuration
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false
        },
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ]
      };
      _peerConnection = await createPeerConnection(configuration);

      // Add local audio track and set up transceivers
      final tracks = _localStream?.getAudioTracks() ?? [];
      final audioTrack = tracks.isNotEmpty ? tracks.first : null;
      if (audioTrack != null) {
        debugPrint('Adding audio track: enabled=${audioTrack.enabled}');
        final sender = await _peerConnection?.addTrack(audioTrack, _localStream!);
        debugPrint('Audio sender added: ${sender != null}');
        
        // Ensure audio is enabled
        audioTrack.enabled = true;
      } else {
        debugPrint('No audio track available!');
      }

      // Remote stream
      _peerConnection?.onTrack = (event) {
        debugPrint('onTrack: ${event.track.kind}, streams: ${event.streams.length}');
        if (event.streams.isNotEmpty) {
          final stream = event.streams[0];
          debugPrint('Remote stream audio tracks: ${stream.getAudioTracks().length}');
          
          // Ensure audio is properly routed
          if (event.track.kind == 'audio') {
            event.track.enabled = true;
            final audioTracks = stream.getAudioTracks();
            if (audioTracks.isNotEmpty) {
              audioTracks.first.enabled = true;
            }
          }
          
          _startCallTimer();
          setState(() => _inCalling = true);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to answer call: $e')),
        );
      }
      _hangUp();
    }
  }

  Future<void> _makeOutgoingCall() async {
    try {
      final callDoc = _firestore.collection('calls').doc(_callDocId);

      // Start call timeout
      _startCallTimeout();

      // Create offer with audio preferences
      final offer = await _peerConnection!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
      });

      debugPrint('Created offer: ${offer.sdp}');
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

  Future<void> _checkAudioState() async {
    if (_localStream == null) {
      debugPrint('No local stream available');
      return;
    }

    final audioTracks = _localStream!.getAudioTracks();
    debugPrint('Audio track count: ${audioTracks.length}');
    
    for (final track in audioTracks) {
      debugPrint('Audio track: enabled=${track.enabled}, muted=${track.muted}, kind=${track.kind}');
    }
  }

  void _startCallTimer() {
    _callStartTime = DateTime.now();
    _durationTimer?.cancel();
    _checkAudioState(); // Check audio state when call starts
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final duration = DateTime.now().difference(_callStartTime!);
      final minutes = duration.inMinutes.toString().padLeft(2, '0');
      final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
      setState(() {
        _callDuration = '$minutes:$seconds';
      });
    });
  }

  bool _isHangingUp = false;

  Future<void> _hangUp() async {
    if (_isHangingUp) return;
    _isHangingUp = true;
    _durationTimer?.cancel();
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

    _callSub?.cancel();
    _callerCandidatesSub?.cancel();
    _calleeCandidatesSub?.cancel();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callStatus = widget.isIncoming ? 
      (_inCalling ? 'Connected' : 'Answering call from ${widget.calleeName}...') :
      (_inCalling ? 'Connected' : 'Calling ${widget.calleeName}...');

    final duration = _inCalling ? _callDuration : '';

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Caller avatar
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withAlpha(51),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.calleeName[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Caller name
                  Text(
                    widget.calleeName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Call status
                  Text(
                    callStatus,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  if (_inCalling) ...[
                    const SizedBox(height: 8),
                    // Call duration
                    Text(
                      duration,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Call controls
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(128),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute button
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: 'Mute',
                    isActive: _isMuted,
                    onPressed: () {
                      if (_localStream != null) {
                        final audioTrack = _localStream!.getAudioTracks().first;
                        audioTrack.enabled = !audioTrack.enabled;
                        setState(() => _isMuted = !audioTrack.enabled);
                      }
                    },
                  ),
                  // End call button
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _hangUp,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Speaker button
                  _buildControlButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    label: 'Speaker',
                    isActive: _isSpeakerOn,
                    onPressed: () {
                      setState(() => _isSpeakerOn = !_isSpeakerOn);
                      if (_peerConnection != null) {
                        final audioTrack = _localStream?.getAudioTracks().first;
                        if (audioTrack != null) {
                          final constraints = {
                            'audio': {
                              'echoCancellation': true,
                              'noiseSuppression': true,
                              'autoGainControl': true,
                              'googAutoGainControl': true,
                              'googAutoGainControl2': true,
                              'googEchoCancellation': true,
                              'googEchoCancellation2': true,
                              'googNoiseSuppression': true,
                              'googNoiseSuppression2': true,
                              'googHighpassFilter': true,
                              'googAudioMirroring': _isSpeakerOn,
                            }
                          };
                          audioTrack.applyConstraints(constraints);
                        }
                      }
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

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
              color: isActive ? Colors.white.withAlpha(77) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.white : Colors.white70,
          ),
        ),
      ],
    );
  }
}
