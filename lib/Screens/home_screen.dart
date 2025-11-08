import 'package:flutter/material.dart';
import 'sections/contacts_screen.dart';
import 'sections/chats_screen.dart';
import 'sections/call_history_screen.dart';
import '../Services/call_service.dart';
import '../Services/firebase_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final CallService _callService = CallService();
  
  final List<Widget> _screens = [
    const ContactsScreen(),
    const ChatsScreen(),
    const CallHistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeCallService();
  }

  Future<void> _initializeCallService() async {
    final currentUser = FirebaseService().currentUser;
    if (currentUser != null) {
      _callService.initialize(currentUser.uid, context);
    }
  }

  @override
  void dispose() {
    _callService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NetCalling'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // TODO: Implement menu
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.contacts),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.call),
            label: 'Calls',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Implement action based on current tab
          switch (_currentIndex) {
            case 0: // Contacts
              // Add new contact
              break;
            case 1: // Chats
              // Start new chat
              break;
            case 2: // Calls
              // Make new call
              break;
          }
        },
        child: Icon(_currentIndex == 1 ? Icons.message : Icons.add),
      ),
    );
  }
}
