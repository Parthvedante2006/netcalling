import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'call_screen.dart';

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

      Navigator.pop(context, true);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callerId: widget.callerId,
            calleeId: widget.calleeId,
            calleeName: widget.callerName,
            isIncoming: true,
            callId: widget.callId,
          ),
        ),
      );
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
        backgroundColor: Colors.black87,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Hero(
                tag: 'caller_avatar_${widget.callerId}',
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.blueGrey.shade800,
                  child: Text(
                    widget.callerName[0].toUpperCase(),
                    style: const TextStyle(fontSize: 40, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.callerName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              if (_isCallActive) ...[
                const Text(
                  'Incoming call...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
              ] else ...[
                const Text(
                  'Call ended',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ],
              if (_isProcessing) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ],
              const Spacer(),
              if (_isCallActive) ...[
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FloatingActionButton(
                        backgroundColor: Colors.red,
                        onPressed: _isProcessing ? null : _handleRejectCall,
                        child: const Icon(Icons.call_end, color: Colors.white),
                      ),
                      FloatingActionButton(
                        backgroundColor: Colors.green,
                        onPressed: _isProcessing ? null : _handleAcceptCall,
                        child: const Icon(Icons.call, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}
