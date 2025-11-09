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
    debugPrint('Starting call setup...');
    final hasPermission = await _requestMicrophonePermission();
    if (!hasPermission) {
      debugPrint('Microphone permission denied');
      throw Exception('Microphone permission denied');
    }

    try {
      debugPrint('Initializing WebRTC...');
      // Initialize WebRTC with optimized settings
      if (WebRTC.platformIsAndroid) {
        await WebRTC.initialize(options: {
          'enableHardwareAcceleration': true,
          'androidAudioConfiguration': {
            'audioSource': 'voice_communication',
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true
          }
        });
      }

      // Get user media with enhanced audio settings
      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googHighpassFilter': true,
          'googEchoCancellation': true,
          'googNoiseSuppression': true,
          'googAutoGainControl': true,
        },
        'video': false
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      final audioTracks = _localStream?.getAudioTracks();
      if (audioTracks == null || audioTracks.isEmpty) {
        throw Exception('No audio track found');
      }
      
      // Enable audio processing
      for (var track in audioTracks) {
        track.enabled = true;
        final settings = await track.getSettings();
        debugPrint('Audio track settings: $settings');
      }

      // Create peer connection with optimized configuration
      final Map<String, dynamic> configuration = {
        'iceServers': [
          {
            'urls': [
              'stun:stun1.l.google.com:19302',
              'stun:stun2.l.google.com:19302',
            ],
          },
          {
            'urls': 'turn:relay.metered.ca:80',
            'username': 'f5b151f05d214d2e060bdf1d',
            'credential': 'QXu0WBhcGE8vLg01',
          },
          {
            'urls': 'turn:relay.metered.ca:443',
            'username': 'f5b151f05d214d2e060bdf1d',
            'credential': 'QXu0WBhcGE8vLg01',
          },
          {
            'urls': 'turn:relay.metered.ca:443?transport=tcp',
            'username': 'f5b151f05d214d2e060bdf1d',
            'credential': 'QXu0WBhcGE8vLg01',
          },
        ],
        'sdpSemantics': 'unified-plan',
        'iceTransportPolicy': 'all',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'iceCandidatePoolSize': 1,
      };
      debugPrint('Creating peer connection...');
      _peerConnection = await createPeerConnection(configuration);

      // Enhanced audio track handling
      final audioTrack = audioTracks.first;
      debugPrint('Adding audio track to peer connection...');
      final rtpSender = await _peerConnection?.addTrack(audioTrack, _localStream!);
      debugPrint('RTP Sender created: ${rtpSender != null}');
      
      // Configure audio track
      audioTrack.enabled = true;
      try {
        await audioTrack.applyConstraints({
          'autoGainControl': true,
          'echoCancellation': true,
          'noiseSuppression': true,
        });
        debugPrint('Applied audio constraints to local track');
      } catch (e) {
        debugPrint('Warning: Could not apply audio constraints: $e');
      }

      // Enhanced remote audio handling
      _peerConnection?.onTrack = (event) async {
        if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
          debugPrint('Remote audio track received');
          final stream = event.streams.first;
          
          // Configure remote audio track
          final audioTracks = stream.getAudioTracks();
          for (var track in audioTracks) {
            track.enabled = true;
            debugPrint('Remote audio track enabled: ${track.id}');
          }
          
          // Set remote stream
          _remoteRenderer.srcObject = stream;
          
          // Configure audio output
          await Helper.setSpeakerphoneOn(_isSpeakerOn);
          
          // Double-check audio routing after a short delay
          Future.delayed(const Duration(milliseconds: 500), () async {
            await Helper.setSpeakerphoneOn(_isSpeakerOn);
          });
          
          _startCallTimer();
          setState(() => _inCalling = true);
          
          // Log audio track details
          final settings = await event.track.getSettings();
          debugPrint('Remote audio track settings: $settings');
        }
      };

      // Enhanced ICE candidate handling
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) async {
        debugPrint('New ICE candidate: ${candidate.candidate != null}');
        if (candidate.candidate == null) return;
        
        try {
          final collection = widget.isIncoming ? 'calleeCandidates' : 'callerCandidates';
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
            debugPrint('ICE candidate added to Firestore');
          }
        } catch (e) {
          debugPrint('Error saving ICE candidate: $e');
        }
      };

      // Handle ICE connection state changes
      _peerConnection?.onIceConnectionState = (state) {
        debugPrint('ICE Connection State: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          debugPrint('ICE Connection failed - attempting reconnection');
          _attemptReconnection();
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          debugPrint('ICE Connection established');
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

      debugPrint('Setting up call document...');
      _callDocId = widget.isIncoming ? widget.callId : _firestore.collection('calls').doc().id;
      debugPrint('Call ID: $_callDocId');

      if (widget.isIncoming) {
        debugPrint('Handling incoming call...');
        await _handleIncomingCall();
      } else {
        debugPrint('Making outgoing call...');
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
      debugPrint('Handling incoming call for ID: $_callDocId');
      final callDoc = _firestore.collection('calls').doc(_callDocId);
      final callData = await callDoc.get();
      if (!callData.exists) {
        debugPrint('Call document no longer exists');
        throw Exception('Call no longer exists');
      }

      final data = callData.data()!;
      final offer = data['offer'];
      if (offer == null) {
        debugPrint('No offer found in call data');
        throw Exception('No offer in call');
      }

      debugPrint('Setting remote description from offer...');
      await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']));
      debugPrint('Remote description set successfully');

      debugPrint('Creating answer...');
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      debugPrint('Answer created, setting local description...');
      await _peerConnection!.setLocalDescription(answer);
      debugPrint('Local description set successfully');

      debugPrint('Updating call document with answer...');
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

      debugPrint('Creating WebRTC offer...');
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      debugPrint('Offer created, setting local description...');
      await _peerConnection!.setLocalDescription(offer);
      debugPrint('Local description set successfully');

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
      debugPrint('Attempting to reconnect WebRTC connection...');

      // First, check if peer connection is still valid
      if (_peerConnection == null) {
        throw Exception('PeerConnection is null');
      }

      // Try to restart ICE
      try {
        await _peerConnection!.restartIce();
        debugPrint('ICE restart initiated');
      } catch (e) {
        debugPrint('ICE restart failed: $e');
      }

      // Re-enable all audio tracks
      if (_localStream != null) {
        for (var track in _localStream!.getAudioTracks()) {
          track.enabled = true;
          debugPrint('Re-enabled local audio track: ${track.id}');
        }
      }

      if (_remoteRenderer.srcObject != null) {
        for (var track in _remoteRenderer.srcObject!.getAudioTracks()) {
          track.enabled = true;
          debugPrint('Re-enabled remote audio track: ${track.id}');
        }
      }

      // Re-configure audio output
      try {
        await Helper.setSpeakerphoneOn(_isSpeakerOn);
        debugPrint('Reconfigured audio output');
      } catch (e) {
        debugPrint('Audio output reconfiguration failed: $e');
      }

      // Update call status in Firestore
      if (_callDocId != null) {
        await _firestore.collection('calls').doc(_callDocId).update({
          'reconnecting': true,
          'timestamp': FieldValue.serverTimestamp(),
          'lastError': null,
        });
        debugPrint('Updated call status in Firestore');
      }

      // Set reconnection timeout
      Future.delayed(const Duration(seconds: 15), () async {
        if (!_inCalling && mounted && !_isHangingUp) {
          debugPrint('Reconnection timeout reached');
          try {
            if (_callDocId != null) {
              await _firestore.collection('calls').doc(_callDocId).update({
                'state': 'failed',
                'lastError': 'Reconnection timeout',
              });
            }
          } catch (e) {
            debugPrint('Error updating call state: $e');
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not reconnect. Ending call...')),
            );
            _hangUp();
          }
        }
      });

    } catch (e) {
      debugPrint('Reconnection attempt failed: $e');
      if (_callDocId != null) {
        try {
          await _firestore.collection('calls').doc(_callDocId).update({
            'state': 'failed',
            'lastError': e.toString(),
          });
        } catch (e) {
          debugPrint('Error updating call state: $e');
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reconnect: $e')),
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Debug Call: ${widget.calleeName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end),
            color: Colors.red,
            onPressed: _hangUp,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status Section
            _buildDebugSection(
              'Connection Status',
              [
                'Call State: ${_inCalling ? "Connected" : "Connecting"}',
                'Connection: $_networkStatus',
                'Packet Loss: $_packetLoss%',
                'Call Duration: $_callDuration',
                'Remote Description Set: $_remoteDescSet',
              ],
            ),

            // Local Stream Info
            _buildDebugSection(
              'Local Stream',
              [
                if (_localStream != null) ...[
                  'Active: ${_localStream?.active}',
                  'ID: ${_localStream?.id}',
                  ..._localStream!.getAudioTracks().map((track) => 
                    'Audio Track: ${track.id} (enabled: ${track.enabled})')
                ] else
                  'No Local Stream',
              ],
            ),

            // Remote Stream Info
            _buildDebugSection(
              'Remote Stream',
              [
                if (_remoteRenderer.srcObject != null) ...[
                  'Active: ${_remoteRenderer.srcObject?.active}',
                  'ID: ${_remoteRenderer.srcObject?.id}',
                  ..._remoteRenderer.srcObject!.getAudioTracks().map((track) => 
                    'Audio Track: ${track.id} (enabled: ${track.enabled})')
                ] else
                  'No Remote Stream',
              ],
            ),

            // Audio Controls
            _buildDebugSection(
              'Audio Controls',
              [
                'Muted: $_isMuted',
                'Speaker: $_isSpeakerOn',
              ],
            ),

            // Control Buttons
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                    label: Text(_isMuted ? 'Unmute' : 'Mute'),
                    onPressed: () {
                      if (_localStream != null) {
                        final track = _localStream!.getAudioTracks().first;
                        track.enabled = !track.enabled;
                        setState(() => _isMuted = !track.enabled);
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    icon: Icon(_isSpeakerOn ? Icons.volume_up : Icons.volume_down),
                    label: Text(_isSpeakerOn ? 'Speaker On' : 'Speaker Off'),
                    onPressed: () async {
                      try {
                        final newState = !_isSpeakerOn;
                        await Helper.setSpeakerphoneOn(newState);
                        if (mounted) {
                          setState(() => _isSpeakerOn = newState);
                        }
                      } catch (e) {
                        debugPrint('Speaker toggle error: $e');
                      }
                    },
                  ),
                ],
              ),
            ),

            // Debug Actions
            _buildDebugSection(
              'Debug Actions',
              [
                TextButton(
                  child: const Text('Check Audio Tracks'),
                  onPressed: () async {
                    if (_localStream != null) {
                      final tracks = _localStream!.getAudioTracks();
                      for (var track in tracks) {
                        final settings = await track.getSettings();
                        debugPrint('Local track ${track.id} settings: $settings');
                      }
                    }
                    if (_remoteRenderer.srcObject != null) {
                      final tracks = _remoteRenderer.srcObject!.getAudioTracks();
                      for (var track in tracks) {
                        final settings = await track.getSettings();
                        debugPrint('Remote track ${track.id} settings: $settings');
                      }
                    }
                  },
                ),
                TextButton(
                  child: const Text('Re-enable Audio Tracks'),
                  onPressed: () {
                    if (_localStream != null) {
                      for (var track in _localStream!.getAudioTracks()) {
                        track.enabled = true;
                      }
                    }
                    if (_remoteRenderer.srcObject != null) {
                      for (var track in _remoteRenderer.srcObject!.getAudioTracks()) {
                        track.enabled = true;
                      }
                    }
                    setState(() => _isMuted = false);
                  },
                ),
                TextButton(
                  child: const Text('Toggle Audio Route'),
                  onPressed: () async {
                    await Helper.setSpeakerphoneOn(!_isSpeakerOn);
                    setState(() => _isSpeakerOn = !_isSpeakerOn);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugSection(String title, List<dynamic> items) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            ...items.map((item) {
              if (item is Widget) return item;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  item.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }


}
