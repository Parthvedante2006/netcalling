import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../Screens/incoming_call_screen.dart';

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _incomingCallSubscription;
  String? _userId;
  BuildContext? _context;

  void initialize(String userId, BuildContext context) {
    _userId = userId;
    _context = context;
    _listenForIncomingCalls();
  }

  void _listenForIncomingCalls() {
    if (_userId == null) {
      debugPrint('CallService: No user ID available');
      return;
    }

    debugPrint('CallService: Starting incoming call listener for user $_userId');
    _incomingCallSubscription?.cancel();
    
    _incomingCallSubscription = _firestore
        .collection('calls')
        .where('calleeId', isEqualTo: _userId)
        .where('state', isEqualTo: 'offer')
        .snapshots()
        .listen(
          (snapshot) async {
            debugPrint('CallService: Received snapshot with ${snapshot.docs.length} calls');
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                debugPrint('CallService: New incoming call detected');
                final call = change.doc.data()!;
                await _handleIncomingCall(change.doc.id, call);
              }
            }
          },
          onError: (error) {
            debugPrint('CallService: Error in call listener: $error');
          },
        );
  }

  Future<void> _handleIncomingCall(String callId, Map<String, dynamic> callData) async {
    if (_context == null) return;

    final callerId = callData['callerId'] as String;
    final callerName = callData['callerName'] as String;
    final callTimestamp = callData['createdAt'] as Timestamp?;
    
    // Check if call is not too old (more than 30 seconds)
    if (callTimestamp != null) {
      final callAge = DateTime.now().difference(callTimestamp.toDate());
      if (callAge.inSeconds > 30) {
        await _rejectCall(callId, reason: 'missed');
        return;
      }
    }
    
    // Show incoming call screen with timeout
    if (_context!.mounted) {
      bool? accepted;
      try {
        accepted = await showDialog<bool>(
          context: _context!,
          barrierDismissible: false,
          builder: (context) => IncomingCallScreen(
            callId: callId,
            callerId: callerId,
            callerName: callerName,
            calleeId: _userId!,
          ),
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            Navigator.of(_context!).pop(false);
            return false;
          },
        );
      } catch (e) {
        debugPrint('Error showing incoming call: $e');
        accepted = false;
      }

      if (accepted != true) {
        // Call was rejected, missed, or dialog was dismissed
        await _rejectCall(callId, reason: 'rejected');
      }
    }
  }

  Future<void> _rejectCall(String callId, {String reason = 'rejected'}) async {
    try {
      final callRef = _firestore.collection('calls').doc(callId);
      await callRef.update({
        'state': reason,
        'endedAt': FieldValue.serverTimestamp(),
      });
      
      // Clean up ICE candidates
      await _cleanupCallData(callRef);
      
      // Delete the call document
      await callRef.delete();
    } catch (e) {
      debugPrint('Error rejecting call: $e');
    }
  }

  Future<void> _cleanupCallData(DocumentReference callRef) async {
    try {
      // Clean up caller candidates
      final callerCandidates = await callRef.collection('callerCandidates').get();
      for (var doc in callerCandidates.docs) {
        await doc.reference.delete();
      }
      
      // Clean up callee candidates
      final calleeCandidates = await callRef.collection('calleeCandidates').get();
      for (var doc in calleeCandidates.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Error cleaning up call data: $e');
    }
  }

  void dispose() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = null;
    _userId = null;
    _context = null;
  }
}