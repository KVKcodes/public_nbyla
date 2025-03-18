import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/auth_service.dart';
import '../../services/presence_service.dart';
import './chat_screen.dart';

class ChatDashboard extends StatefulWidget {
  const ChatDashboard({super.key});

  @override
  State<ChatDashboard> createState() => _ChatDashboardState();
}

class _ChatDashboardState extends State<ChatDashboard> {
  final _authService = AuthService();
  final _firestore = FirebaseFirestore.instance;
  final _presenceService = PresenceService();
  bool _isSpacesSelected = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showActiveOnly = false;

  @override
  void initState() {
    super.initState();
    _updateUserPresence();
  }

  void _updateUserPresence() {
    _presenceService.updatePresence(isOnline: true);
  }

  @override
  void dispose() {
    _presenceService.updatePresence(isOnline: false);
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _getUsersStream() {
    final currentUser = FirebaseAuth.instance.currentUser;
    return _firestore
        .collection('users')
        .where('email', isNotEqualTo: currentUser?.email)
        .snapshots();
  }

  Stream<int> _getUnreadCount(String recipientEmail) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return Stream.value(0);

    final emails = [currentUser.email!, recipientEmail]..sort();
    final chatId = '${emails[0]}_${emails[1]}';

    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isEqualTo: recipientEmail)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/nbyla.svg',
                    height: 28,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF5F2EEA),
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Hello, ${user?.displayName ?? 'User'}',
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.grey[600],
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () async {
                      await _authService.signOut();
                      if (mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    icon: Icon(
                      Icons.logout,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey[200]!,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _buildTabButton('Spaces', _isSpacesSelected, null),
                  _buildTabButton('DMs', !_isSpacesSelected, () {
                    setState(() => _isSpacesSelected = false);
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  _buildFilterChip('All', !_showActiveOnly, () {
                    setState(() => _showActiveOnly = false);
                  }),
                  const SizedBox(width: 8),
                  _buildFilterChip('Active', _showActiveOnly, () {
                    setState(() => _showActiveOnly = true);
                  }),
                ],
              ),
            ),
            Expanded(
              child: _isSpacesSelected
                ? ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildSpaceItem(
                        'Kvk Siddartha\'s Space',
                        'assets/nbyla.svg',
                      ),
                    ],
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: _getUsersStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Error: ${snapshot.error}'),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final users = snapshot.data?.docs ?? [];
                      
                      if (users.isEmpty) {
                        return const Center(
                          child: Text('No users found'),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final userData = users[index].data() as Map<String, dynamic>;
                          final name = userData['name'] ?? 'Unknown User';
                          final email = userData['email'] ?? '';
                          final isOnline = userData['isOnline'] ?? false;
                          
                          // Filter based on search query
                          if (_searchQuery.isNotEmpty &&
                              !name.toLowerCase().contains(_searchQuery) &&
                              !email.toLowerCase().contains(_searchQuery)) {
                            return const SizedBox.shrink();
                          }
                          
                          // Filter for active users
                          if (_showActiveOnly && !isOnline) {
                            return const SizedBox.shrink();
                          }

                          // Get unread messages count
                          return StreamBuilder<int>(
                            stream: _getUnreadCount(email),
                            builder: (context, unreadSnapshot) {
                              final unreadCount = unreadSnapshot.data ?? 0;
                              
                              return _buildDMItem(
                                name,
                                email,
                                'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=random',
                                'Active',
                                isOnline: isOnline,
                                unreadCount: unreadCount,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String text, bool isSelected, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected
                  ? const Color(0xFF5F2EEA)
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected
                ? const Color(0xFF5F2EEA)
                : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback? onTap) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: isSelected 
            ? const Color(0xFFF7F5FF)
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected 
              ? const Color(0xFF5F2EEA)
              : Colors.grey[600],
          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildSpaceItem(String name, String logoPath) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F5FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: SvgPicture.asset(
            logoPath,
            height: 20,
            colorFilter: const ColorFilter.mode(
              Color(0xFF5F2EEA),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(title: name, recipientEmail: '',),
          ),
        );
      },
    );
  }

  Widget _buildDMItem(
    String name,
    String email,
    String avatarUrl,
    String time, {
    bool isOnline = false,
    int unreadCount = 0,
  }) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundImage: NetworkImage(avatarUrl),
            radius: 24,
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(email),
      trailing: unreadCount > 0
          ? Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              title: name,
              recipientEmail: email,
            ),
          ),
        );
      },
    );
  }
} 