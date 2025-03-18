import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nbyla/services/notification_service.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String title;
  final String recipientEmail;
  
  const ChatScreen({
    super.key, 
    required this.title,
    required this.recipientEmail,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _chatId;
  String? _replyToId;
  String? _replyToContent;
  bool _isFirstLoad = true;
  StreamSubscription<QuerySnapshot>? _messageSubscription;
  // final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupChat();
    _setupMessageListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markMessagesAsRead();
    }
  }

  Future<void> _setupChat() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Create a unique chat ID by combining emails alphabetically
    final emails = [currentUser.email!, widget.recipientEmail]..sort();
    _chatId = '${emails[0]}_${emails[1]}';
  }

  Stream<QuerySnapshot> _getMessagesStream() {
    if (_chatId == null) return const Stream.empty();
    
    return _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  void _setupMessageListener() {
    if (_chatId == null) return;

    _messageSubscription = _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .where('senderId', isEqualTo: widget.recipientEmail)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        _markMessagesAsRead();
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    if (_chatId == null) return;
    
    final batch = _firestore.batch();
    final messages = await _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .where('senderId', isEqualTo: widget.recipientEmail)
        .where('read', isEqualTo: false)
        .get();

    for (var doc in messages.docs) {
      batch.update(doc.reference, {'read': true});
    }

    await batch.commit();
  }

  void _sendMessage() async {
    if (_messageController.text.isEmpty || _chatId == null) return;
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final messageText = _messageController.text;
    final replyToId = _replyToId;

    _messageController.clear();
    setState(() {
      _replyToId = null;
      _replyToContent = null;
    });

    try {
      // Send message to Firestore
      final docRef = await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .add({
            'content': messageText,
            'senderId': currentUser.email,
            'timestamp': FieldValue.serverTimestamp(),
            'sent': false,
            'read': false,
            'replyTo': replyToId,
          });

      await docRef.update({'sent': true});

      // Update chat document
      await _firestore.collection('chats').doc(_chatId).set({
        'lastMessage': messageText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': currentUser.email,
      }, SetOptions(merge: true));

      // Send notification via AWS Lambda
      await NotificationService().sendNotification(
        widget.recipientEmail,
        messageText,
      );

      _scrollToBottom();
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _startReply(String messageId, String content) {
    setState(() {
      _replyToId = messageId;
      _replyToContent = content;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyToId = null;
      _replyToContent = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMessageList(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getMessagesStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting && _isFirstLoad) {
          return const Center(child: CircularProgressIndicator());
        }

        final messages = snapshot.data?.docs ?? [];

        // Handle first load scroll
        if (_isFirstLoad && messages.isNotEmpty) {
          _isFirstLoad = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index].data() as Map<String, dynamic>;
            final isCurrentUser = message['senderId'] == _auth.currentUser?.email;
            final timestamp = message['timestamp'] as Timestamp?;
            final time = timestamp != null 
                ? DateFormat('HH:mm').format(timestamp.toDate())
                : '';
            final read = message['read'] ?? false;
            final sent = message['sent'] ?? false;
            final replyTo = message['replyTo'];
            
            return _buildMessage(
              message['content'],
              isCurrentUser,
              time,
              read,
              sent,
              messages[index].id,
              replyTo != null ? messages.firstWhere((m) => m.id == replyTo)['content'] : null,
              replyTo,
            );
          },
        );
      },
    );
  }

  Widget _buildMessage(
    String content,
    bool isCurrentUser,
    String time,
    bool read,
    bool sent,
    String messageId,
    String? replyToContent,
    String? replyToId,
  ) {
    // Create a key for this message
    _messageKeys[messageId] = _messageKeys[messageId] ?? GlobalKey();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Dismissible(
        key: Key(messageId),
        direction: DismissDirection.startToEnd,
        dismissThresholds: const {
          DismissDirection.startToEnd: 0.25,
        },
        confirmDismiss: (direction) async {
          _startReply(messageId, content);
          return false;
        },
        background: Container(
          padding: const EdgeInsets.only(left: 16),
          alignment: Alignment.centerLeft,
          child: ShaderMask(  // Add subtle gradient effect
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.purple.withOpacity(0.5), Colors.transparent],
              ).createShader(bounds);
            },
            child: const Icon(
              Icons.reply,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        child: Align(
          alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (replyToContent != null)
                GestureDetector(
                  onTap: () => _scrollToMessage(replyToId!),
                  child: _buildReplyPreview(replyToContent, isCurrentUser),
                ),
              Container(
                key: _messageKeys[messageId],
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                margin: EdgeInsets.only(
                  left: isCurrentUser ? 64 : 8,
                  right: isCurrentUser ? 8 : 64,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _highlightedMessageId == messageId
                      ? (isCurrentUser ? Colors.purple[100] : Colors.grey[300])
                      : (isCurrentUser ? const Color(0xFFF3E5F5) : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (isCurrentUser) _buildMessageStatus(sent, read),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageStatus(bool sent, bool read) {
    if (!sent) {
      return const Icon(Icons.access_time, size: 14, color: Colors.grey);
    } else if (read) {
      return const Icon(Icons.done_all, size: 14, color: Colors.blue);
    } else {
      return const Icon(Icons.done_all, size: 14, color: Colors.grey);
    }
  }

  Widget _buildMessageInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyToContent != null)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 20,
                  color: Colors.purple[200],
                  margin: const EdgeInsets.only(right: 8),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reply to message',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _replyToContent!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _cancelReply,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border(
              top: BorderSide(color: Colors.grey[200]!),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReplyPreview(String replyContent, bool isCurrentUser) {
    return Container(
      margin: EdgeInsets.only(
        left: isCurrentUser ? 64 : 8,
        right: isCurrentUser ? 8 : 64,
        bottom: 4,
      ),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 2,
            height: 20,
            color: Colors.purple[200],
            margin: const EdgeInsets.only(right: 8),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reply to message',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyContent,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[800],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToMessage(String messageId) {
    final messageKey = _messageKeys[messageId];
    if (messageKey?.currentContext != null) {
      Scrollable.ensureVisible(
        messageKey!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,  // Center the message
      ).then((_) {
        // Briefly highlight the message
        setState(() {
          _highlightedMessageId = messageId;
        });
        Future.delayed(const Duration(seconds: 1), () {
          setState(() {
            _highlightedMessageId = null;
          });
        });
      });
    }
  }
} 