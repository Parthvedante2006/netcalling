import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import '../call_screen.dart';
import '../../Services/firebase_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  DocumentSnapshot<Map<String, dynamic>>? _result;
  String? _error;
  int _selectedTab = 0; // 0 = Search, 1 = Contacts

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final query = _searchController.text.trim();
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    if (query.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Enter a username to search';
      });
      return;
    }

    try {
      final snapshot = await FirebaseService().getUserByUsername(query);

      if (snapshot == null || !snapshot.exists) {
        setState(() {
          _error = 'No user found for "$query"';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _result = snapshot;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Search failed: $e';
        _isLoading = false;
      });
    }
  }

  String _generateChatId(String uid1, String uid2) {
    return uid1.hashCode <= uid2.hashCode ? '$uid1-$uid2' : '$uid2-$uid1';
  }

  Future<void> _addToContacts() async {
    if (_result == null) return;

    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final contactUid = _result!.data()?['uid'] as String;
    
    // Check if already in contacts
    final isAlreadyContact = await FirebaseService().isContact(contactUid);
    if (isAlreadyContact) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact already exists')),
        );
      }
      return;
    }

    final result = await FirebaseService().addContact(
      contactUid: contactUid,
      contactName: _result!.data()?['name'] ?? 'Unknown',
      contactUsername: _result!.data()?['username'] ?? '',
      contactEmail: _result!.data()?['email'] ?? '',
    );

    if (mounted) {
      if (result == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[800]!.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(0, 'Search', Icons.search),
              ),
              Expanded(
                child: _buildTabButton(1, 'Contacts', Icons.contacts),
              ),
            ],
          ),
        ),

        // Content based on selected tab
        Expanded(
          child: _selectedTab == 0 ? _buildSearchTab() : _buildContactsTab(),
        ),
      ],
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [Colors.blue[400]!, Colors.purple[400]!],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[400],
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[400],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Search by username',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
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
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[400]!, Colors.purple[400]!],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _doSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Search',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[900]!.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[300], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red[300]),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_result != null) ...[
            Card(
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
                      (_result!.data()?['name'] ?? 'N')[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  _result!.data()?['name'] ?? 'No name',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '@${_result!.data()?['username'] ?? ''}\n${_result!.data()?['email'] ?? ''}',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionButton(
                      icon: Icons.chat,
                      tooltip: 'Message',
                      onPressed: () async {
                        final currentUid = FirebaseAuth.instance.currentUser!.uid;
                        final otherUid = _result!.data()?['uid'] as String;
                        final chatId = _generateChatId(currentUid, otherUid);

                        final chatDoc =
                            FirebaseFirestore.instance.collection('chats').doc(chatId);
                        final chatSnapshot = await chatDoc.get();

                        if (!chatSnapshot.exists) {
                          await chatDoc.set({
                            'participants': [currentUid, otherUid],
                            'userNames': {
                              currentUid: FirebaseAuth.instance.currentUser!.displayName ?? 'Me',
                              otherUid: _result!.data()?['name'] ?? 'Unknown',
                            },
                            'lastMessage': '',
                            'lastTimestamp': FieldValue.serverTimestamp(),
                          });
                        }

                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                chatId: chatId,
                                otherUserName: _result!.data()?['name'] ?? 'Unknown',
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
                        final calleeUid = _result!.data()?['uid'] as String;
                        final calleeName = _result!.data()?['name'] ?? '';

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallScreen(
                              callerId: currentUid,
                              calleeId: calleeUid,
                              calleeName: calleeName,
                            ),
                          ),
                        );
                      },
                    ),
                    _buildActionButton(
                      icon: Icons.person_add,
                      tooltip: 'Add to Contacts',
                      color: Colors.blue[400],
                      onPressed: _addToContacts,
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_result == null && _error == null && !_isLoading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      size: 64,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Search users by their username',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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

  Widget _buildContactsTab() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Please log in to view contacts'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseService().getContacts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
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

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final contact = snapshot.data!.docs[index];
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
                  '@$contactUsername\n$contactEmail',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                isThreeLine: true,
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

                        if (mounted) {
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
                          if (mounted) {
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
    );
  }
}