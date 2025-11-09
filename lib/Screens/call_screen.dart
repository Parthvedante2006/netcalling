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
      // Set default audio settings - speaker on by default for calls
      setState(() => _isSpeakerOn = true);
      
      // Configure speakerphone - this is critical for audio playback
      try {
        await Helper.setSpeakerphoneOn(true);
        debugPrint('Speakerphone initialized to ON');
      } on UnimplementedError catch (e, st) {
        debugPrint('Helper.setSpeakerphoneOn not implemented: $e\n$st');
      } catch (e, st) {
        debugPrint('Error setting speakerphone on: $e\n$st');
      }
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
        try {
          final settings = track.getSettings();
          debugPrint('Audio track settings: $settings');
        } on UnimplementedError catch (e, st) {
            debugPrint('getSettings not implemented on this platform: $e\n$st');
          } catch (e, st) {
            debugPrint('Error reading audio track settings: $e\n$st');
          }
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

      // (transceiver addition omitted for compatibility with this flutter_webrtc version)

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
          debugPrint('Remote audio track received: ${event.track.id}');
          final stream = event.streams.first;
          
          // Configure remote audio track - CRITICAL for audio playback
          final audioTracks = stream.getAudioTracks();
          for (var track in audioTracks) {
            track.enabled = true;
            debugPrint('Remote audio track enabled: ${track.id}');
            
            // Ensure track is unmuted
            if (track.muted != null) {
              // Force enable the track
              track.enabled = true;
            }
          }
          
          // Set remote stream to renderer (required for audio playback)
          _remoteRenderer.srcObject = stream;
          
          // Force renderer to play audio by setting it up properly
          try {
            await _remoteRenderer.initialize();
          } catch (e) {
            debugPrint('Renderer already initialized: $e');
          }
          
          // Configure audio output immediately
          try {
            await Helper.setSpeakerphoneOn(_isSpeakerOn);
            debugPrint('Audio output configured: speaker=$_isSpeakerOn');
          } on UnimplementedError catch (e, st) {
            debugPrint('setSpeakerphoneOn not implemented: $e\n$st');
          } catch (e, st) {
            debugPrint('Error configuring audio output: $e\n$st');
          }
          
          // Re-configure audio routing multiple times to ensure it works
          for (var delay in [100, 300, 500, 1000]) {
            Future.delayed(Duration(milliseconds: delay), () async {
              try {
                // Re-enable remote audio track
                for (var track in stream.getAudioTracks()) {
                  if (!track.enabled) {
                    track.enabled = true;
                    debugPrint('Re-enabled remote audio track at ${delay}ms: ${track.id}');
                  }
                }
                
                // Re-configure audio output
            try {
              await Helper.setSpeakerphoneOn(_isSpeakerOn);
                } on UnimplementedError {
                  // Ignore - not implemented on this platform
                }
              } catch (e) {
                debugPrint('Error in delayed audio setup at ${delay}ms: $e');
              }
            });
          }
          
          if (mounted) {
          _startCallTimer();
          setState(() => _inCalling = true);
          }
          
          // Log audio track details
          try {
            final settings = event.track.getSettings();
            debugPrint('Remote audio track settings: $settings');
          } on UnimplementedError catch (e, st) {
            debugPrint('Remote track getSettings not implemented: $e\n$st');
          } catch (e, st) {
            debugPrint('Error getting remote track settings: $e\n$st');
          }
          
          debugPrint('Remote audio track setup completed');
        }
      };

      // Enhanced ICE candidate handling
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) async {
        if (candidate.candidate == null || candidate.candidate!.isEmpty) {
          debugPrint('ICE candidate gathering completed');
          return;
        }

        debugPrint('New ICE candidate: ${candidate.sdpMid} - ${candidate.candidate?.substring(0, candidate.candidate!.length > 50 ? 50 : candidate.candidate!.length)}');

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
            debugPrint('ICE candidate added to Firestore: $collection');
          }
        } catch (e, st) {
          debugPrint('Error adding ICE candidate: $e\n$st');
        }
      };

      // Handle ICE connection state changes (merged handlers)
      _peerConnection?.onIceConnectionState = (state) {
        debugPrint('ICE Connection State: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Establishing connection...')),
            );
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                   state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          debugPrint('ICE Connection established');
          // Ensure remote audio is playing when connection is established
          if (_remoteRenderer.srcObject != null) {
            final audioTracks = _remoteRenderer.srcObject!.getAudioTracks();
            for (var track in audioTracks) {
              track.enabled = true;
              debugPrint('Ensured remote audio track enabled after ICE connection: ${track.id}');
            }
            // Re-configure audio output
            Helper.setSpeakerphoneOn(_isSpeakerOn).catchError((e) {
              debugPrint('Error setting speaker after ICE connection: $e');
            });
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          debugPrint('ICE Connection failed - attempting reconnection');
          _attemptReconnection();
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          debugPrint('ICE Connection disconnected - attempting reconnection');
          _attemptReconnection();
        }
      };

      // Enhanced connection state handling
      _peerConnection?.onConnectionState = (state) {
        debugPrint('Connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          debugPrint('WebRTC connection established');
          // Ensure audio tracks are enabled
          if (_localStream != null) {
            for (var track in _localStream!.getAudioTracks()) {
              track.enabled = !_isMuted;
            }
          }
          if (_remoteRenderer.srcObject != null) {
            for (var track in _remoteRenderer.srcObject!.getAudioTracks()) {
              track.enabled = true;
              debugPrint('Remote audio track enabled after connection: ${track.id}');
            }
            // Configure audio output
            Helper.setSpeakerphoneOn(_isSpeakerOn).catchError((e) {
              debugPrint('Error setting speaker after connection: $e');
            });
          }
          if (!_inCalling && mounted) {
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
      try {
        // Modify offer SDP to ensure audio is properly configured
        String offerSdp = offer['sdp'] ?? '';
        // Ensure audio direction allows sending and receiving
        if (offerSdp.contains('a=recvonly') && !offerSdp.contains('a=sendrecv')) {
          offerSdp = offerSdp.replaceAll('a=recvonly', 'a=sendrecv');
        }
        if (offerSdp.contains('a=sendonly') && !offerSdp.contains('a=sendrecv')) {
          offerSdp = offerSdp.replaceAll('a=sendonly', 'a=sendrecv');
        }
        
        final remoteDesc = RTCSessionDescription(offerSdp, offer['type']);
        await _peerConnection!.setRemoteDescription(remoteDesc);
        _remoteDescSet = true; // Mark remote description as set for incoming calls
        debugPrint('Remote description set successfully');
      } catch (e) {
        debugPrint('Error setting remote description from offer: $e');
      }

      debugPrint('Creating answer...');
      // Create answer with proper audio configuration
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      
      // Modify SDP to ensure audio is properly configured
      String modifiedSdp = answer.sdp ?? '';
      // Ensure audio is not muted in SDP
      if (modifiedSdp.contains('a=sendonly')) {
        modifiedSdp = modifiedSdp.replaceAll('a=sendonly', 'a=sendrecv');
      }
      if (modifiedSdp.contains('a=recvonly') && !modifiedSdp.contains('a=sendrecv')) {
        // Ensure we can both send and receive audio
        modifiedSdp = modifiedSdp.replaceAll('a=recvonly', 'a=sendrecv');
      }
      
      final modifiedAnswer = RTCSessionDescription(modifiedSdp, answer.type);
      
      debugPrint('Answer created, setting local description...');
      await _peerConnection!.setLocalDescription(modifiedAnswer);
      debugPrint('Local description set successfully');

      debugPrint('Updating call document with answer...');
      await callDoc.update({
        'answer': {'sdp': modifiedSdp, 'type': modifiedAnswer.type},
        'state': 'answered',
      });

      // Only listen for caller candidates after remote description is set
      _callerCandidatesSub =
          callDoc.collection('callerCandidates').snapshots().listen((snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data != null && _peerConnection != null) {
              try {
                // Only add candidates after remote description is set
                // Use _remoteDescSet flag since remoteDescription property doesn't exist
                if (_remoteDescSet) {
                _peerConnection!.addCandidate(RTCIceCandidate(
                  data['candidate'],
                  data['sdpMid'],
                  data['sdpMLineIndex'],
                ));
                  debugPrint('Added caller ICE candidate after remote description set');
                } else {
                  debugPrint('Skipping ICE candidate - remote description not set yet');
                  // Store candidate to add later
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_remoteDescSet && _peerConnection != null) {
                      try {
                        _peerConnection!.addCandidate(RTCIceCandidate(
                          data['candidate'],
                          data['sdpMid'],
                          data['sdpMLineIndex'],
                        ));
                        debugPrint('Added stored caller ICE candidate');
                      } catch (e) {
                        debugPrint('Error adding stored ICE candidate: $e');
                      }
                    }
                  });
                }
              } catch (e, st) {
                debugPrint('Error adding ICE candidate (callee side): $e\n$st');
              }
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
      // Create offer with proper audio configuration
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      
      // Modify SDP to ensure audio is properly configured
      String modifiedSdp = offer.sdp ?? '';
      // Ensure audio direction is sendrecv (send and receive)
      if (!modifiedSdp.contains('a=sendrecv')) {
        // Replace any restrictive audio directions
        modifiedSdp = modifiedSdp.replaceAll('a=sendonly', 'a=sendrecv');
        modifiedSdp = modifiedSdp.replaceAll('a=recvonly', 'a=sendrecv');
      }
      
      final modifiedOffer = RTCSessionDescription(modifiedSdp, offer.type);
      
      debugPrint('Offer created, setting local description...');
      await _peerConnection!.setLocalDescription(modifiedOffer);
      debugPrint('Local description set successfully');

      final callData = {
        'callerId': widget.callerId,
        'calleeId': widget.calleeId,
        'callerName': widget.calleeName,
        'offer': {'sdp': modifiedSdp, 'type': modifiedOffer.type},
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
          try {
            debugPrint('Setting remote description from answer...');
            
            // Modify answer SDP to ensure audio is properly configured
            String answerSdp = answer['sdp'] ?? '';
            // Ensure audio direction allows receiving
            if (answerSdp.contains('a=sendonly') && !answerSdp.contains('a=sendrecv')) {
              answerSdp = answerSdp.replaceAll('a=sendonly', 'a=sendrecv');
            }
            
            final remoteDesc = RTCSessionDescription(answerSdp, answer['type']);
            await _peerConnection!.setRemoteDescription(remoteDesc);
            _remoteDescSet = true;
            debugPrint('Remote description set successfully from answer');
            
            // After setting remote description, ensure audio tracks are enabled
            Future.delayed(const Duration(milliseconds: 100), () {
              if (_localStream != null) {
                for (var track in _localStream!.getAudioTracks()) {
                  track.enabled = !_isMuted;
                  debugPrint('Local audio track enabled: ${track.id}');
                }
              }
              
              // Configure audio output
              Helper.setSpeakerphoneOn(_isSpeakerOn).catchError((e) {
                debugPrint('Error setting speaker: $e');
              });
              
              if (mounted) {
            setState(() => _inCalling = true);
                _startCallTimer();
              }
            });
          } catch (e) {
            debugPrint('Error setting remote description from answer: $e');
          }
        }
      });

      // Only listen for callee candidates after remote description is set
      _calleeCandidatesSub =
          callDoc.collection('calleeCandidates').snapshots().listen((snap) {
        for (final doc in snap.docChanges) {
            if (doc.type == DocumentChangeType.added) {
            final data = doc.doc.data();
            if (data != null && _peerConnection != null) {
              try {
                // Only add candidates after remote description is set
                // Use _remoteDescSet flag since remoteDescription property doesn't exist
                if (_remoteDescSet) {
                  _peerConnection!.addCandidate(RTCIceCandidate(
                  data['candidate'],
                  data['sdpMid'],
                  data['sdpMLineIndex'],
                ));
                  debugPrint('Added callee ICE candidate after remote description set');
                } else {
                  debugPrint('Skipping ICE candidate - remote description not set yet');
                  // Store candidate to add later
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_remoteDescSet && _peerConnection != null) {
                      try {
                        _peerConnection!.addCandidate(RTCIceCandidate(
                          data['candidate'],
                          data['sdpMid'],
                          data['sdpMLineIndex'],
                        ));
                        debugPrint('Added stored callee ICE candidate');
              } catch (e) {
                        debugPrint('Error adding stored ICE candidate: $e');
                      }
                    }
                  });
                }
              } catch (e) {
                debugPrint('Error adding ICE candidate (caller side): $e');
              }
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
        try {
          await Helper.setSpeakerphoneOn(_isSpeakerOn);
          debugPrint('Reconfigured audio output');
        } on UnimplementedError catch (e) {
          debugPrint('setSpeakerphoneOn not implemented during reconnection: $e');
        }
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.grey[900]!,
                Colors.black,
                Colors.black,
              ],
            ),
          ),
        child: Column(
          children: [
              // Top spacing
              const Spacer(flex: 2),
              
              // Caller Avatar
              Hero(
                tag: 'caller_avatar_${widget.calleeId}',
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue[400]!,
                        Colors.purple[400]!,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.calleeName.isNotEmpty 
                          ? widget.calleeName[0].toUpperCase() 
                          : 'C',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Caller Name
              Text(
                widget.calleeName,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Call Status
              Text(
                _inCalling ? 'Connected' : 'Connecting...',
                style: TextStyle(
                  fontSize: 16,
                  color: _inCalling ? Colors.green[300] : Colors.orange[300],
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Call Duration
              if (_inCalling)
                Text(
                  _callDuration,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              
              // Network Status (subtle)
              if (_inCalling && _networkStatus != 'Good Connection')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _networkStatus == 'Poor Connection' 
                            ? Icons.signal_wifi_off
                            : Icons.signal_cellular_alt,
                        size: 16,
                        color: Colors.orange[300],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _networkStatus,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[300],
                        ),
                      ),
                    ],
                  ),
                ),
              
              const Spacer(flex: 3),
              
            // Control Buttons
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                    // Mute Button
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
                    
                    // Speaker Button
                    _buildControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                      label: 'Speaker',
                      isActive: _isSpeakerOn,
                    onPressed: () async {
                      try {
                        final newState = !_isSpeakerOn;
                        try {
                          await Helper.setSpeakerphoneOn(newState);
                        } on UnimplementedError catch (e) {
                          debugPrint('setSpeakerphoneOn not implemented: $e');
                        }
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

              const SizedBox(height: 40),
              
              // Hang Up Button
              GestureDetector(
                onTap: _hangUp,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red[600],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              
              const SizedBox(height: 60),
            ],
          ),
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
          children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive 
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
              border: Border.all(
                color: isActive 
                    ? Colors.white.withOpacity(0.5)
                    : Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }


}
