import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../auth_service.dart';

class CompanyDashboard extends StatefulWidget {
  const CompanyDashboard({super.key});

  @override
  State<CompanyDashboard> createState() => _CompanyDashboardState();
}

class _CompanyDashboardState extends State<CompanyDashboard> {
  bool _isLoading = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  Stream<QuerySnapshot>? _notificationStream;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _notificationStream = userSession.userId != null
        ? firestore
            .collection('company_notifications')
            .where('userId', isEqualTo: userSession.userId)
            .orderBy('createdAt', descending: true)
            .limit(10)
            .snapshots()
        : null;
    _initNotifications();
    _saveFcmToken();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _saveFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && userSession.userId != null) {
        await userSession.saveFCMToken(token);
      }
    } catch (e) {
    }
  }

  void _logout() async {
    setState(() => _isLoading = true);
    await userSession.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Widget _buildNotificationButton() {
    if (userSession.userId == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _notificationStream,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs
                .where((doc) => (doc.data() as Map<String, dynamic>)['read'] == false)
                .length ??
            0;
        if (unreadCount != _unreadCount && mounted) {
          setState(() => _unreadCount = unreadCount);
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: _openNotificationsSheet,
              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openNotificationsSheet() {
    if (_notificationStream == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Notifications',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _notificationStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final notifications = [...snapshot.data?.docs ?? []];
                      notifications.sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final bData = b.data() as Map<String, dynamic>;
                        final aDate = aData['createdAt'] as Timestamp?;
                        final bDate = bData['createdAt'] as Timestamp?;
                        return (bDate?.toDate() ?? DateTime(1970))
                            .compareTo(aDate?.toDate() ?? DateTime(1970));
                      });
                      final visibleNotifications = notifications.take(30).toList();
                      if (notifications.isEmpty) {
                        return const Center(
                          child: Text('Aucune notification pour le moment'),
                        );
                      }
                      return ListView.separated(
                        itemCount: visibleNotifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = visibleNotifications[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final title = (data['title'] ?? 'Notification').toString();
                          final body = (data['body'] ?? '').toString();
                          final isUnread = data['read'] == false;
                          return ListTile(
                            title: Text(
                              title,
                              style: TextStyle(
                                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isUnread
                                ? Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null,
                            onTap: () async {
                              Navigator.pop(context);
                              if (!doc.reference.id.contains('demo')) {
                                await doc.reference.update({'read': true});
                              }
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace entreprise'),
        backgroundColor: const Color(0xFF00BCD4),
        foregroundColor: Colors.white,
        actions: [
          _buildNotificationButton(),
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Déconnexion'),
                  content: const Text(
                    'Voulez-vous vraiment vous déconnecter ?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Non'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _logout();
                      },
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Oui'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business, size: 80, color: const Color(0xFF00BCD4)),
            const SizedBox(height: 20),
            const Text(
              'Bienvenue dans votre espace entreprise',
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 10),
            const Text(
              'Compte entreprise créé',
              style: TextStyle(color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}


