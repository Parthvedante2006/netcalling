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
      debugPrint('HomeScreen: Initializing CallService for user ${currentUser.uid}');
      _callService.initialize(currentUser.uid, context);
    } else {
      debugPrint('HomeScreen: No current user found for CallService initialization');
      // Show a snackbar to notify the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error initializing call service. Please try logging in again.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-initialize call service when dependencies change (e.g., after navigation)
    _initializeCallService();
  }

  @override
  void dispose() {
    _callService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        elevation: 0,
        title: const Text(
          'NetCalling',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              // TODO: Implement search
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {
              // TODO: Implement menu
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey[900]!,
              Colors.black,
              Colors.black,
            ],
          ),
        ),
        child: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            navigationBarTheme: NavigationBarThemeData(
              labelTextStyle: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return const TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
                }
                return TextStyle(color: Colors.grey[400], fontWeight: FontWeight.normal);
              }),
            ),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: _currentIndex,
            indicatorColor: Colors.blue[400]!.withOpacity(0.3),
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.contacts_outlined, color: Colors.grey[400]),
                selectedIcon: const Icon(Icons.contacts, color: Colors.white),
                label: 'Contacts',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline, color: Colors.grey[400]),
                selectedIcon: const Icon(Icons.chat, color: Colors.white),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: Icon(Icons.call_outlined, color: Colors.grey[400]),
                selectedIcon: const Icon(Icons.call, color: Colors.white),
                label: 'Calls',
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
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
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: FloatingActionButton(
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Icon(
            _currentIndex == 1 ? Icons.message : Icons.add,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
