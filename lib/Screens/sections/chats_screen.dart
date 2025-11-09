import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUid)
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

          // For each chat, fetch the latest message's timestamp and sort chats by it
          Future<List<Map<String, dynamic>>> sortedChatsFuture = Future.wait(
            chats.map((chat) async {
              final msgSnap = await FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chat.id)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .limit(1)
                  .get();
              final latestMsg = msgSnap.docs.isNotEmpty ? msgSnap.docs.first : null;
              final Map<String, dynamic> chatMap = {};
              final chatData = chat.data();
              if (chatData != null && chatData is Map<String, dynamic>) {
                chatMap.addAll(chatData);
              }
              chatMap['latestTimestamp'] = latestMsg != null ? latestMsg['timestamp'] : null;
              chatMap['latestMsg'] = latestMsg;
              chatMap['doc'] = chat;
              return chatMap;
            }).toList(),
          ).then((chatMaps) {
            chatMaps.sort((a, b) {
              final aTs = a['latestTimestamp'];
              final bTs = b['latestTimestamp'];
              if (aTs == null && bTs == null) return 0;
              if (aTs == null) return 1;
              if (bTs == null) return -1;
              final aTime = aTs is Timestamp ? aTs.toDate().millisecondsSinceEpoch : (aTs as int);
              final bTime = bTs is Timestamp ? bTs.toDate().millisecondsSinceEpoch : (bTs as int);
              return bTime.compareTo(aTime);
            });
            return chatMaps;
          });

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: sortedChatsFuture,
            builder: (context, sortedSnap) {
              if (sortedSnap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final sortedChats = sortedSnap.data ?? [];
              if (sortedChats.isEmpty) return const Center(child: Text('No active chats'));

              return ListView.builder(
                itemCount: sortedChats.length,
                itemBuilder: (context, index) {
                  final chatMap = sortedChats[index];
                  final chatDoc = chatMap['doc'] as QueryDocumentSnapshot;
                  final participants = List<String>.from(chatMap['participants'] ?? []);
                  final otherUid = participants.firstWhere((uid) => uid != currentUid, orElse: () => '');
                  final otherName = chatMap['userNames']?[otherUid] ?? 'Unknown';
                  final latestMsg = chatMap['latestMsg'] as QueryDocumentSnapshot?;
                  String subtitle = 'Tap to chat';
                  String senderName = '';
                  if (latestMsg != null) {
                    final msgData = latestMsg.data() as Map<String, dynamic>;
                    final senderId = msgData['senderId'] ?? '';
                    final text = msgData['text'] ?? '';
                    subtitle = text.isNotEmpty ? text : subtitle;
                    // Fetch sender username from users collection
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(senderId).get(),
                      builder: (context, userSnap) {
                        if (userSnap.connectionState == ConnectionState.done && userSnap.hasData) {
                          final userData = userSnap.data?.data() as Map<String, dynamic>?;
                          senderName = userData?['username'] ?? '';
                        }
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(otherName),
                          subtitle: Text(senderName.isNotEmpty ? '$senderName: $subtitle' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  chatId: chatDoc.id,
                                  otherUserName: otherName,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  }
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(otherName),
                    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: chatDoc.id,
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
        },
      ),
    );
  }
}