import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUid)
          .orderBy('lastTimestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final chats = snapshot.data!.docs;
        if (chats.isEmpty) return const Center(child: Text('No active chats'));

        return ListView.builder(
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chat = chats[index];
            final participants = List<String>.from(chat['participants'] ?? []);
            final otherUid = participants.firstWhere((uid) => uid != currentUid, orElse: () => '');
            final otherName = chat['userNames']?[otherUid] ?? 'Unknown';

            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(otherName),
              subtitle: Text(chat['lastMessage'] ?? 'Tap to chat'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      chatId: chat.id,
                      otherUserName: otherName,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}