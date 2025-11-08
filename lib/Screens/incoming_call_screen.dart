import 'package:flutter/material.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 60,
              child: Text(
                callerName[0].toUpperCase(),
                style: const TextStyle(fontSize: 40),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              callerName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Incoming call...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: () async {
                      // Decline call
                      Navigator.pop(context, false);
                    },
                    child: const Icon(Icons.call_end),
                  ),
                  FloatingActionButton(
                    backgroundColor: Colors.green,
                    onPressed: () {
                      // Accept call
                      Navigator.pop(context, true);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CallScreen(
                            callerId: callerId,
                            calleeId: calleeId,
                            calleeName: callerName,
                            isIncoming: true,
                            callId: callId,
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.call),
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