import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import './call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerId;
  final String callerName;
  final String calleeId;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _isProcessing = false;
  StreamSubscription<DocumentSnapshot>? _callSubscription;
  bool _isCallActive = true;

  @override
  void initState() {
    super.initState();
    _listenForCallChanges();
  }

  void _listenForCallChanges() {
    _callSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists || snapshot.data()?['state'] == 'cancelled') {
          debugPrint('Call was cancelled or deleted');
          if (mounted) {
            setState(() => _isCallActive = false);
            Navigator.pop(context, false);
          }
        }
      },
      onError: (error) {
        debugPrint('Error listening to call changes: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Call error: $error')),
          );
        }
      },
    );
  }

  Future<void> _handleRejectCall() async {
    if (_isProcessing || !_isCallActive) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final callRef = FirebaseFirestore.instance.collection('calls').doc(widget.callId);
      final callDoc = await callRef.get();
      
      if (!callDoc.exists) {
        debugPrint('Call document no longer exists');
        if (mounted) Navigator.pop(context, false);
        return;
      }

      await callRef.update({
        'state': 'rejected',
        'endedAt': FieldValue.serverTimestamp(),
      });

      // Clean up ICE candidates
      await _cleanupCallData(callRef);
      
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      debugPrint('Error rejecting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to reject call')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cleanupCallData(DocumentReference callRef) async {
    try {
      final callerCandidates = await callRef.collection('callerCandidates').get();
      for (var doc in callerCandidates.docs) {
        await doc.reference.delete();
      }
      final calleeCandidates = await callRef.collection('calleeCandidates').get();
      for (var doc in calleeCandidates.docs) {
        await doc.reference.delete();
      }
      await callRef.delete();
    } catch (e) {
      debugPrint('Error cleaning up call data: $e');
    }
  }

  Future<void> _handleAcceptCall() async {
    if (_isProcessing || !_isCallActive) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final callRef = FirebaseFirestore.instance.collection('calls').doc(widget.callId);
      final callDoc = await callRef.get();
      
      if (!callDoc.exists) {
        debugPrint('Call no longer exists');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call no longer exists')),
          );
          Navigator.pop(context, false);
        }
        return;
      }

      await callRef.update({
        'state': 'answering',
        'answeredAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      debugPrint('Transitioning to call screen...');
      if (mounted) {
        Navigator.pop(context, true);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CallScreen(
              callerId: widget.callerId,
              calleeId: widget.calleeId,
              calleeName: widget.callerName, // Using caller's name as callee name for display
              isIncoming: true,
              callId: widget.callId,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error accepting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to accept call')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _handleRejectCall();
        return false;
      },
      child: Scaffold(
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Hero(
                  tag: 'caller_avatar_${widget.callerId}',
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
                        widget.callerName.isNotEmpty
                            ? widget.callerName[0].toUpperCase()
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
                Text(
                  widget.callerName,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                if (_isCallActive) ...[
                  Text(
                    'Incoming call...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.orange[300],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else ...[
                  Text(
                    'Call ended',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red[300],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (_isProcessing) ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ],
                const Spacer(flex: 3),
                if (_isCallActive) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Reject Button
                        Column(
                          children: [
                            GestureDetector(
                              onTap: _isProcessing ? null : _handleRejectCall,
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
                            const SizedBox(height: 8),
                            Text(
                              'Decline',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        // Accept Button
                        Column(
                          children: [
                            GestureDetector(
                              onTap: _isProcessing ? null : _handleAcceptCall,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.green[600],
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.4),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.call,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Accept',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

}
