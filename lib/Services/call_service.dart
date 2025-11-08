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
    if (_userId == null) return;

    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = _firestore
        .collection('calls')
        .where('calleeId', isEqualTo: _userId)
        .where('state', isEqualTo: 'offer')
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final call = change.doc.data()!;
          await _handleIncomingCall(change.doc.id, call);
        }
      }
    });
  }

  Future<void> _handleIncomingCall(String callId, Map<String, dynamic> callData) async {
    if (_context == null) return;

    final callerId = callData['callerId'] as String;
    final callerName = callData['callerName'] as String;
    
    // Show incoming call screen
    if (_context!.mounted) {
      final accepted = await showDialog<bool>(
        context: _context!,
        barrierDismissible: false,
        builder: (context) => IncomingCallScreen(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          calleeId: _userId!,
        ),
      );

      if (accepted != true) {
        // Call was rejected or dialog was dismissed
        await _rejectCall(callId);
      }
    }
  }

  Future<void> _rejectCall(String callId) async {
    try {
      final callRef = _firestore.collection('calls').doc(callId);
      await callRef.update({'state': 'rejected'});
      
      // Clean up after a short delay
      await Future.delayed(const Duration(seconds: 2));
      await callRef.delete();
    } catch (e) {
      debugPrint('Error rejecting call: $e');
    }
  }

  void dispose() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = null;
    _userId = null;
    _context = null;
  }
}