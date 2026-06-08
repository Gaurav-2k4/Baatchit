import 'package:cloud_firestore/cloud_firestore.dart';

/// Service class for managing chat-related Firestore operations
class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generate a consistent chat ID from two user IDs
  /// Always returns IDs in alphabetical order: "aaa_bbb"
  String generateChatId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  /// Create a new chat document in Firestore
  Future<void> createChat({
    required String chatId,
    required String uid1,
    required String uid2,
  }) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    final exists = await chatRef.get();

    if (!exists.exists) {
      await chatRef.set({
        'participants': [uid1, uid2],
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread': {uid1: 0, uid2: 0},
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Send a message in a chat
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String text,
  }) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    final messagesRef = chatRef.collection('messages');

    // Add the message to the messages subcollection
    await messagesRef.add({
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });

    // Update the chat document with last message info
    await chatRef.update({
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unread.$receiverId': FieldValue.increment(1),
    });
  }

  /// Mark all messages as read for a user
  Future<void> markMessagesAsRead({
    required String chatId,
    required String userId,
  }) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    
    // Reset unread count for the user
    await chatRef.update({
      'unread.$userId': 0,
    });

    // Optionally: Mark all messages as read in the messages subcollection
    final messagesSnapshot = await chatRef
        .collection('messages')
        .where('senderId', isNotEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in messagesSnapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  /// Get messages stream for a chat
  Stream<QuerySnapshot> getMessagesStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Delete a chat (optional feature)
  Future<void> deleteChat(String chatId) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    
    // Delete all messages first
    final messagesSnapshot = await chatRef.collection('messages').get();
    final batch = _firestore.batch();
    
    for (final doc in messagesSnapshot.docs) {
      batch.delete(doc.reference);
    }
    
    // Delete the chat document
    batch.delete(chatRef);
    await batch.commit();
  }

  /// Add user to friends list
  Future<void> addFriend(String userId, String friendId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('friends')
        .doc(friendId)
        .set({'addedAt': FieldValue.serverTimestamp()});
  }

  /// Remove user from friends list
  Future<void> removeFriend(String userId, String friendId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('friends')
        .doc(friendId)
        .delete();
  }
}
