import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';

class ChatScreen extends StatefulWidget {
  final String? conversationId;
  final String? otherUserId;
  final String? otherUserName;

  const ChatScreen({
    super.key,
    this.conversationId,
    this.otherUserId,
    this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  int _unreadCount = 0;

  bool _isUploading = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    if (userSession.userId == null) return;
    final conversationRef = FirebaseFirestore.instance
        .collection('messages')
        .doc(widget.conversationId);
    await conversationRef.update({
      'unreadCount_${userSession.userId}': 0,
    });
  }

  Future<void> _sendMessage({String? text, String? type, String? fileUrl, String? fileName}) async {
    final messageText = (text ?? '').trim();
    if (messageText.isEmpty && type == null) return;
    if (userSession.userId == null) return;

    try {
      final conversationRef = FirebaseFirestore.instance
          .collection('messages')
          .doc(widget.conversationId);

      final messageRef = conversationRef.collection('chat_messages').doc();

      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userSession.userId)
          .get();
      final senderData = senderDoc.data() ?? {};
      final senderName =
          (senderData['name'] ?? senderData['email'] ?? userSession.userId ?? 'Utilisateur').toString();

      final messageData = <String, dynamic>{
        'senderId': userSession.userId,
        'senderName': senderName,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (type != null) {
        messageData['type'] = type;
        if (fileUrl != null) messageData['fileUrl'] = fileUrl;
        if (fileName != null) messageData['fileName'] = fileName;
      }
      if (messageText.isNotEmpty) {
        messageData['text'] = messageText;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.set(messageRef, messageData);

        final displayMessage = type != null && messageText.isEmpty
            ? (type == 'image' ? 'Photo' : (fileName ?? 'Fichier'))
            : messageText;

        final participants = [userSession.userId, widget.otherUserId]..sort();
        transaction.set(conversationRef, {
          'participants': participants,
          'lastMessage': displayMessage,
          'senderName': senderName,
          'createdAt': FieldValue.serverTimestamp(),
          'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
          'unreadCount_${userSession.userId}': 0,
        }, SetOptions(merge: true));
      });

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur envoi message: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      setState(() => _isUploading = true);
      final picked = await _imagePicker.pickImage(source: source, imageQuality: 80);
      if (picked == null) {
        setState(() => _isUploading = false);
        return;
      }

      final url = await userSession.uploadDocumentToCloudinary(picked.path);
      setState(() => _isUploading = false);
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur lors de l\'envoi de l\'image')),
          );
        }
        return;
      }

      await _sendMessage(type: 'image', fileUrl: url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      setState(() => _isUploading = true);
      final result = await FilePicker.pickFiles();
      if (result == null || result.files.single.path == null) {
        setState(() => _isUploading = false);
        return;
      }

      final path = result.files.single.path!;
      final url = await userSession.uploadDocumentToCloudinary(path);
      setState(() => _isUploading = false);
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur lors de l\'envoi du fichier')),
          );
        }
        return;
      }

      final fileName = result.files.single.name;
      await _sendMessage(type: 'file', fileUrl: url, fileName: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _openAttachmentMenu() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00BCD4)),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF00BCD4)),
              title: const Text('Caméra'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Color(0xFF00BCD4)),
              title: const Text('Fichier'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getAvatarColor(String name) {
    int hash = name.hashCode.abs();
    final colors = [
      const Color(0xFF00BCD4),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFFE91E63),
      const Color(0xFF2196F3),
    ];
    return colors[hash % colors.length];
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ouvrir le lien: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.otherUserName ?? 'Utilisateur';
    final avatarColor = _getAvatarColor(userName);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: avatarColor,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        leading: Badge.count(
          backgroundColor: Colors.red,
          count: _unreadCount,
          maxCount: 99,
          isLabelVisible: _unreadCount > 0,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: avatarColor,
                child: Text(
                  userName.isNotEmpty
                      ? userName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'En ligne',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('messages')
                  .doc(widget.conversationId)
                  .collection('chat_messages')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucun message. Envoyez le premier message.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == userSession.userId;
                    final String? type = data['type'] as String?;
                    final text = (data['text'] ?? '').toString();
                    final fileUrl = (data['fileUrl'] ?? '').toString();
                    final fileName = (data['fileName'] ?? '').toString();
                    final createdAt = data['createdAt'] as Timestamp?;
                    final time = createdAt != null
                        ? '${createdAt.toDate().hour.toString().padLeft(2, '0')}:${createdAt.toDate().minute.toString().padLeft(2, '0')}'
                        : '';

                    Widget? mediaContent;
                    if (type == 'image' && fileUrl.isNotEmpty) {
                      mediaContent = InkWell(
                        onTap: () => _openUrl(fileUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            fileUrl,
                            width: 220,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 220,
                              height: 150,
                              color: Colors.black26,
                              child: const Icon(Icons.broken_image, color: Colors.white),
                            ),
                          ),
                        ),
                      );
                    } else if (type == 'file' && fileUrl.isNotEmpty) {
                      mediaContent = InkWell(
                        onTap: () => _openUrl(fileUrl),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.white24 : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                           child: Row(
                             children: [
                               Container(
                                 width: 40,
                                 height: 40,
                                 decoration: BoxDecoration(
                                   color: isMe ? Colors.white30 : const Color(0xFFE0E0E0),
                                   borderRadius: BorderRadius.circular(8),
                                 ),
                                 child: const Icon(Icons.insert_drive_file, color: Color(0xFF00BCD4)),
                               ),
                               const SizedBox(width: 12),
                               Expanded(
                                 child: Column(
                                   crossAxisAlignment: CrossAxisAlignment.start,
                                   children: [
                                     Text(
                                       fileName.isNotEmpty ? fileName : 'Fichier',
                                       style: TextStyle(
                                         color: isMe ? Colors.white : Colors.black87,
                                         fontWeight: FontWeight.w600,
                                       ),
                                       maxLines: 1,
                                       overflow: TextOverflow.ellipsis,
                                     ),
                                     const SizedBox(height: 4),
                                     Text(
                                       'Ouvrir le fichier',
                                       style: TextStyle(
                                         color: isMe ? Colors.white70 : const Color(0xFF00BCD4),
                                         fontSize: 12,
                                       ),
                                     ),
                                   ],
                                 ),
                               ),
                             ],
                           ),
                        ),
                      );
                    }

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? avatarColor : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 0),
                            bottomRight: Radius.circular(isMe ? 0 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (text.isNotEmpty && type != null)
                              Text(
                                text,
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            if (text.isNotEmpty && type != null)
                              const SizedBox(height: 8),
                            if (mediaContent != null) mediaContent!,
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isMe ? Colors.white70 : Colors.black54,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.done_all,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                ],
                              ],
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
          Container(
            padding: EdgeInsets.only(
              left: 10,
              right: 10,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 10,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
            ),
      child: Row(
        children: [
          IconButton(
            onPressed: _isUploading ? null : _openAttachmentMenu,
            icon: Icon(Icons.add_photo_alternate, color: avatarColor),
          ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(text: _messageController.text),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: avatarColor,
                  child: IconButton(
                    onPressed: () => _sendMessage(text: _messageController.text),
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
