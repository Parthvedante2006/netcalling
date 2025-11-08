import 'package:flutter/material.dart';
import '../../Services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../call_screen.dart';

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
      if (snapshot == null) {
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

  @override
  Widget build(BuildContext context) {
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
                  decoration: const InputDecoration(
                    labelText: 'Search by username',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : _doSearch,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],

          if (_result != null) ...[
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(_result!['name'] ?? 'No name'),
                subtitle: Text('@${_result!['username'] ?? ''}\n${_result!['email'] ?? ''}'),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chat),
                      onPressed: () {
                        // TODO: Start chat with this user
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Start chat - not implemented')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.call),
                      onPressed: () {
                        final currentUid = FirebaseAuth.instance.currentUser?.uid;
                        final calleeUid = _result!['uid'];
                        final calleeName = _result!['name'] ?? '';
                        if (currentUid == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You are not authenticated')),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallScreen(callerId: currentUid, calleeId: calleeUid, calleeName: calleeName),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],

          // If no search yet, show a helpful hint
          if (_result == null && _error == null && !_isLoading)
            const Expanded(
              child: Center(
                child: Text('Search users by their username'),
              ),
            ),
        ],
      ),
    );
  }
}