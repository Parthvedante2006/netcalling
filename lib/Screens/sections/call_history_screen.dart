import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../call_screen.dart';
import '../sections/chat_screen.dart';
import '../../Services/firebase_service.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _generateChatId(String uid1, String uid2) {
    return uid1.hashCode <= uid2.hashCode ? '$uid1-$uid2' : '$uid2-$uid1';
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: IconButton(
          icon: Icon(icon, color: color ?? Colors.white, size: 20),
          onPressed: onPressed,
        ),
      ),
    );
  }

  bool _matchesSearch(String query, String name, String username, String email) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    return name.toLowerCase().contains(lowerQuery) ||
        username.toLowerCase().contains(lowerQuery) ||
        email.toLowerCase().contains(lowerQuery);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Center(
        child: Text(
          'Please log in to view contacts',
          style: TextStyle(color: Colors.grey[400]),
        ),
      );
    }

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Search contacts',
              labelStyle: TextStyle(color: Colors.grey[400]),
              hintText: 'Search by name, username, or email',
              hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: Colors.grey[400]),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey[800]!.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue[400]!),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),

        // Contacts List
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseService().getContacts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(color: Colors.red[300]),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.contacts_outlined, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text(
                        'No contacts yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Search and add contacts to get started',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }

              // Filter contacts based on search query
              final searchQuery = _searchController.text.trim();
              final filteredContacts = snapshot.data!.docs.where((doc) {
                final contactData = doc.data();
                final contactName = contactData['name'] ?? 'Unknown';
                final contactUsername = contactData['username'] ?? '';
                final contactEmail = contactData['email'] ?? '';
                return _matchesSearch(searchQuery, contactName, contactUsername, contactEmail);
              }).toList();

              if (filteredContacts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text(
                        'No contacts found',
                        style: TextStyle(fontSize: 18, color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try a different search term',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: filteredContacts.length,
                itemBuilder: (context, index) {
                  final contact = filteredContacts[index];
                  final contactData = contact.data();
                  final contactUid = contactData['uid'] as String;
                  final contactName = contactData['name'] ?? 'Unknown';
                  final contactUsername = contactData['username'] ?? '';
                  final contactEmail = contactData['email'] ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.grey[800]!.withOpacity(0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
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
                        ),
                        child: Center(
                          child: Text(
                            contactName.isNotEmpty ? contactName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        contactName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '@$contactUsername',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildActionButton(
                            icon: Icons.chat,
                            tooltip: 'Message',
                            onPressed: () async {
                              final currentUid = FirebaseAuth.instance.currentUser!.uid;
                              final chatId = _generateChatId(currentUid, contactUid);

                              final chatDoc =
                                  FirebaseFirestore.instance.collection('chats').doc(chatId);
                              final chatSnapshot = await chatDoc.get();

                              if (!chatSnapshot.exists) {
                                await chatDoc.set({
                                  'participants': [currentUid, contactUid],
                                  'userNames': {
                                    currentUid: FirebaseAuth.instance.currentUser!.displayName ?? 'Me',
                                    contactUid: contactName,
                                  },
                                  'lastMessage': '',
                                  'lastTimestamp': FieldValue.serverTimestamp(),
                                });
                              }

                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      chatId: chatId,
                                      otherUserName: contactName,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.call,
                            tooltip: 'Call',
                            onPressed: () {
                              final currentUid = FirebaseAuth.instance.currentUser!.uid;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CallScreen(
                                    callerId: currentUid,
                                    calleeId: contactUid,
                                    calleeName: contactName,
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Remove',
                            color: Colors.red[300],
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: Colors.grey[900],
                                  title: const Text(
                                    'Remove Contact',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    'Remove $contactName from your contacts?',
                                    style: TextStyle(color: Colors.grey[300]),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(color: Colors.grey[400]),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: Text(
                                        'Remove',
                                        style: TextStyle(color: Colors.red[300]),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final result = await FirebaseService().removeContact(contactUid);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        result == 'success' 
                                            ? 'Contact removed' 
                                            : result,
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}