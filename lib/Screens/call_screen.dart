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
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _remoteDescSet = false;
  String? _callDocId;
  StreamSubscription? _callSub;
  StreamSubscription? _callerCandidatesSub;
  StreamSubscription? _calleeCandidatesSub;

  bool _inCalling = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  DateTime? _callStartTime;
  Timer? _durationTimer;
  Timer? _statsTimer;
  String _callDuration = '00:00';
  bool _isHangingUp = false;
  
  // Connection quality monitoring
  String _networkStatus = 'Checking...';
  int _packetLoss = 0;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
    _initializeAudio();
    _requestPermissions();
  }

  Future<void> _initializeAudio() async {
    try {
      // Set default audio settings
      setState(() => _isSpeakerOn = true);
      await Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint('Error initializing audio: $e');
    }
  }

  Future<void> _initializeRenderer() async {
    await _remoteRenderer.initialize();
  }

  Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _requestPermissions() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _startCall();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Microphone permission is required for calls')),
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
    final hasPermission = await _requestMicrophonePermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    try {
      // Initialize WebRTC
      if (WebRTC.platformIsAndroid) {
        await WebRTC.initialize(options: {'enableHardwareAcceleration': true});
      }

      // Get user media with basic audio settings
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': false
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      final audioTracks = _localStream?.getAudioTracks();
      if (audioTracks == null || audioTracks.isEmpty) {
        throw Exception('No audio track found');
      }

      // Create peer connection with optimized configuration
      final Map<String, dynamic> configuration = {
        'iceServers': [
          {
            'urls': [
              'stun:stun1.l.google.com:19302',
              'stun:stun2.l.google.com:19302',
            ],
          }
        ],
        'sdpSemantics': 'unified-plan',
      };
      _peerConnection = await createPeerConnection(configuration);

      // Optimized audio track handling
      final audioTrack = audioTracks.first;
      await _peerConnection?.addTrack(audioTrack, _localStream!);
      
      // Enable the audio track
      audioTrack.enabled = true;

      // ✅ Handle remote audio
      _peerConnection?.onTrack = (event) async {
        if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
          debugPrint('Remote audio track received');
          _remoteRenderer.srcObject = event.streams.first;
          await Helper.setSpeakerphoneOn(true); // Route audio to speaker
          _startCallTimer();
          setState(() => _inCalling = true);
        }
      };

      // Handle ICE candidates
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) async {
        if (candidate.candidate == null) return;
        final collection =
            widget.isIncoming ? 'calleeCandidates' : 'callerCandidates';
        if (_callDocId != null) {
          await _firestore
              .collection('calls')
              .doc(_callDocId)
              .collection(collection)
              .add({
            'candidate': candidate.candidate,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'sdpMid': candidate.sdpMid,
          });
        }
      };

      // Enhanced connection state handling
      _peerConnection?.onConnectionState = (state) {
        debugPrint('Connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          debugPrint('WebRTC connection established');
          if (!_inCalling) {
            _startCallTimer();
            setState(() => _inCalling = true);
          }
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          debugPrint('WebRTC connection failed - attempting reconnection');
          _attemptReconnection();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          debugPrint('WebRTC disconnected - attempting reconnection');
          _attemptReconnection();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          debugPrint('WebRTC connection closed');
          _hangUp();
        }
      };
      
      // Add connection monitoring
      _peerConnection?.onIceConnectionState = (state) {
        debugPrint('ICE Connection State: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Establishing connection...')),
            );
          }
        }
      };

      _callDocId =
          widget.isIncoming ? widget.callId : _firestore.collection('calls').doc().id;

      if (widget.isIncoming) {
        await _handleIncomingCall();
      } else {
        await _makeOutgoingCall();
      }
    } catch (e) {
      debugPrint('startCall error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call start failed: $e')),
        );
      }
      _hangUp();
    }
  }

  Future<void> _handleIncomingCall() async {
    try {
      final callDoc = _firestore.collection('calls').doc(_callDocId);
      final callData = await callDoc.get();
      if (!callData.exists) throw Exception('Call no longer exists');

      final data = callData.data()!;
      final offer = data['offer'];
      if (offer == null) throw Exception('No offer in call');

      await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']));

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await callDoc.update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'state': 'answered',
      });

      _callerCandidatesSub =
          callDoc.collection('callerCandidates').snapshots().listen((snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data != null) {
              _peerConnection!.addCandidate(RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ));
            }
          }
        }
      });

      setState(() => _inCalling = true);
    } catch (e) {
      debugPrint('Incoming call error: $e');
      _hangUp();
    }
  }

  Future<void> _makeOutgoingCall() async {
    try {
      debugPrint('Making outgoing call to ${widget.calleeId}');
      final callDoc = _firestore.collection('calls').doc(_callDocId);
      _startCallTimeout();

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      final callData = {
        'callerId': widget.callerId,
        'calleeId': widget.calleeId,
        'callerName': widget.calleeName,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'state': 'offer',
        'createdAt': FieldValue.serverTimestamp(),
        'platform': {
          'caller': 'android',  // or ios, web depending on platform
          'version': '1.0.0',
        },
      };

      debugPrint('Creating call document with ID: ${callDoc.id}');
      await callDoc.set(callData);

      _callSub = callDoc.snapshots().listen((snapshot) async {
        if (!snapshot.exists) {
          _hangUp();
          return;
        }
        final data = snapshot.data();
        if (data == null) return;
        if (data['answer'] != null && !_remoteDescSet) {
          final answer = data['answer'];
          await _peerConnection!
              .setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
          _remoteDescSet = true;
          setState(() => _inCalling = true);
        }
      });

      _calleeCandidatesSub =
          callDoc.collection('calleeCandidates').snapshots().listen((snap) {
        for (final doc in snap.docChanges) {
          if (doc.type == DocumentChangeType.added) {
            final data = doc.doc.data();
            if (data != null) {
              _peerConnection?.addCandidate(RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ));
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Outgoing call error: $e');
      _hangUp();
    }
  }

  Future<void> _startCallTimeout() async {
    await Future.delayed(const Duration(seconds: 30));
    if (!_inCalling && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call was not answered')),
      );
      _hangUp();
    }
  }

  Future<void> _attemptReconnection() async {
    if (!mounted || _isHangingUp) return;

    try {
      // Try to restart ICE connection
      final description = await _peerConnection?.getLocalDescription();
      if (description != null) {
        await _peerConnection?.setLocalDescription(description);
      }

      // Update call status in Firestore to trigger reconnection
      if (_callDocId != null) {
        await _firestore.collection('calls').doc(_callDocId).update({
          'reconnecting': true,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      // Set a timeout for reconnection
      Future.delayed(const Duration(seconds: 10), () {
        if (!_inCalling && mounted && !_isHangingUp) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not reconnect. Ending call...')),
          );
          _hangUp();
        }
      });
    } catch (e) {
      debugPrint('Reconnection attempt failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to reconnect')),
        );
        _hangUp();
      }
    }
  }

  Future<void> _startCallTimer() async {
    _callStartTime = DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final duration = DateTime.now().difference(_callStartTime!);
      final minutes = duration.inMinutes.toString().padLeft(2, '0');
      final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
      setState(() {
        _callDuration = '$minutes:$seconds';
      });
    });
    
    // Start monitoring call stats
    _startStatsMonitoring();
  }

  Future<void> _startStatsMonitoring() async {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peerConnection == null) return;

      try {
        // Get WebRTC stats
        final stats = await _peerConnection!.getStats();
        double totalPackets = 0;
        double packetsLost = 0;
        
        await Future.forEach(stats, (StatsReport report) {
          if (report.type == 'inbound-rtp' && report.values['mediaType'] == 'audio') {
            totalPackets = (report.values['packetsReceived'] ?? 0).toDouble();
            packetsLost = (report.values['packetsLost'] ?? 0).toDouble();
            
            if (totalPackets > 0) {
              setState(() {
                _packetLoss = ((packetsLost / totalPackets) * 100).round();
              });
            }
          }
        });

        // Update network status
        setState(() {
          if (_packetLoss > 10) {
            _networkStatus = 'Poor Connection';
          } else if (_packetLoss > 5) {
            _networkStatus = 'Fair Connection';
          } else {
            _networkStatus = 'Good Connection';
          }
        });

        // Show warning for poor connection
        if (_packetLoss > 15 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Poor network connection detected'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error getting WebRTC stats: $e');
      }
    });
  }

  Future<void> _hangUp() async {
    if (_isHangingUp) return;
    _isHangingUp = true;
    _durationTimer?.cancel();

    try {
      if (_callDocId != null) {
        final ref = _firestore.collection('calls').doc(_callDocId);
        await ref.update({'state': 'ended'});
        final caller = await ref.collection('callerCandidates').get();
        for (var d in caller.docs) {
          await d.reference.delete();
        }
        final callee = await ref.collection('calleeCandidates').get();
        for (var d in callee.docs) {
          await d.reference.delete();
        }
        await ref.delete();
      }
    } catch (_) {}

    await _peerConnection?.close();
    await _localStream?.dispose();
    await _remoteRenderer.dispose();

    _callSub?.cancel();
    _callerCandidatesSub?.cancel();
    _calleeCandidatesSub?.cancel();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callStatus = widget.isIncoming
        ? (_inCalling
            ? 'Connected'
            : 'Answering call from ${widget.calleeName}...')
        : (_inCalling ? 'Connected' : 'Calling ${widget.calleeName}...');

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                            color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(widget.calleeName,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(callStatus,
                      style:
                          const TextStyle(fontSize: 16, color: Colors.white70)),
                  if (_inCalling) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _callDuration,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white54),
                      ),
                    ),
                    if (_networkStatus != 'Checking...') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _packetLoss > 10 
                              ? Colors.red.withOpacity(0.2)
                              : _packetLoss > 5 
                                  ? Colors.orange.withOpacity(0.2)
                                  : Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _packetLoss > 10 
                                  ? Icons.signal_cellular_connected_no_internet_4_bar
                                  : _packetLoss > 5 
                                      ? Icons.signal_cellular_alt_2_bar
                                      : Icons.signal_cellular_alt,
                              size: 16,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _networkStatus,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(128),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: 'Mute',
                    isActive: _isMuted,
                    onPressed: () {
                      if (_localStream != null) {
                        final track = _localStream!.getAudioTracks().first;
                        track.enabled = !track.enabled;
                        setState(() => _isMuted = !track.enabled);
                      }
                    },
                  ),
                  Container(
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.call_end, color: Colors.white),
                      iconSize: 36,
                      onPressed: _hangUp,
                    ),
                  ),
                  _buildControlButton(
                    icon:
                        _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    label: 'Speaker',
                    isActive: _isSpeakerOn,
                    onPressed: () async {
                      try {
                        final newState = !_isSpeakerOn;
                        await Helper.setSpeakerphoneOn(newState);
                        if (mounted) {
                          setState(() => _isSpeakerOn = newState);
                        }
                        // Re-route audio through the selected output
                        if (_localStream != null) {
                          final audioTracks = _localStream!.getAudioTracks();
                          for (var track in audioTracks) {
                            track.enabled = true;
                          }
                        }
                      } catch (e) {
                        debugPrint('Error toggling speaker: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to change audio output')),
                        );
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
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 28),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: isActive ? Colors.white : Colors.white70)),
      ],
    );
  }
}
