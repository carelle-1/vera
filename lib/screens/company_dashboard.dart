import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../auth_service.dart';
import 'chat_screen.dart';

class CompanyDashboard extends StatefulWidget {
  const CompanyDashboard({super.key});

  @override
  State<CompanyDashboard> createState() => _CompanyDashboardState();
}

class _CompanyDashboardState extends State<CompanyDashboard> {
  bool _isLoading = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  Stream<QuerySnapshot>? _notificationStream;
  Stream<QuerySnapshot>? _jobseekersStream;
  Stream<QuerySnapshot>? _solicitationsStream;
  Stream<QuerySnapshot>? _applicationsStream;

  int _currentIndex = 0;
  int _unreadMessageCount = 0;

  // --- Offres ---
  final _offerFormKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _companyController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _salaryController = TextEditingController();
  final _skillsController = TextEditingController();
  String? _contractType;
  DateTime? _expiryDate;
  String? _logoUrl;
  String? _editingOfferId;
  bool _showOfferForm = false;
  final List<String> _contractTypes = [
    'CDI',
    'CDD',
    'Temps partiel',
    'Freelance',
    'Stage',
    'Intérim',
  ];

  // --- Paramètres ---
  final _settingsFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _aboutController = TextEditingController();

  // --- Utilisateurs ---
  String _userSearch = '';

  @override
  void initState() {
    super.initState();
    _notificationStream = userSession.userId != null
        ? firestore
            .collection('company_notifications')
            .where('userId', isEqualTo: userSession.userId)
            .limit(10)
            .snapshots()
        : null;

    if (userSession.userId != null) {
      firestore
          .collection('messages')
          .where('participants', arrayContains: userSession.userId)
          .snapshots()
          .listen((snapshot) {
        final totalUnread = snapshot.docs.fold<int>(0, (sum, doc) {
          final data = doc.data() as Map<String, dynamic>;
          final key = 'unreadCount_${userSession.userId}';
          final value = data[key];
          if (value is int) return sum + value;
          if (value is double) return sum + value.toInt();
          return sum;
        });
        if (mounted) {
          setState(() => _unreadMessageCount = totalUnread);
        }
      });
    }
    _initNotifications();
    _saveFcmToken();
    _loadCompanyProfile();
    _jobseekersStream = firestore.collection('jobseekers').snapshots();
    _solicitationsStream = userSession.userId != null
        ? firestore
            .collection('solicitations')
            .where('companyId', isEqualTo: userSession.userId)
            .snapshots()
        : null;

    if (userSession.userId != null) {
      firestore
          .collection('job_offers')
          .where('userId', isEqualTo: userSession.userId)
          .snapshots()
          .listen((offerSnapshot) {
        final offerIds = offerSnapshot.docs.map((doc) => doc.id).toList();
        if (offerIds.isEmpty) {
          _applicationsStream = null;
          return;
        }
        _applicationsStream = firestore
            .collection('applications')
            .where('offerId', whereIn: offerIds)
            .snapshots();
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _companyController.dispose();
    _contactEmailController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _descriptionController.dispose();
    _salaryController.dispose();
    _skillsController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  Future<void> _initNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _saveFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && userSession.userId != null) {
        await userSession.saveFCMToken(token);
      }
    } catch (e) {}
  }

  Future<void> _loadCompanyProfile() async {
    if (userSession.userId == null) return;
    try {
      final doc =
          await firestore.collection('users').doc(userSession.userId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _websiteController.text = data['website'] ?? '';
          _aboutController.text = data['about'] ?? '';
          if (_companyController.text.isEmpty) {
            _companyController.text = data['name'] ?? '';
          }
        });
      }
    } catch (e) {}
  }

  void _logout() async {
    setState(() => _isLoading = true);
    await userSession.logout();
    if (mounted) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATIONS (icône AppBar)
  // ---------------------------------------------------------------------------
  Widget _buildNotificationButton() {
    if (userSession.userId == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _notificationStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotificationsSheet,
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final unreadCount = docs
            .where((doc) =>
                (doc.data() as Map<String, dynamic>)['read'] == false)
            .length;

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
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

  Future<List<QueryDocumentSnapshot>> _loadNotifications() async {
    if (userSession.userId == null) return [];

    try {
      final snapshot = await firestore
          .collection('company_notifications')
          .where('userId', isEqualTo: userSession.userId)
          .limit(50)
          .get();
      return snapshot.docs;
    } catch (e) {
      throw Exception('Impossible de charger les notifications: $e');
    }
  }

  void _openNotificationsSheet() {
    if (userSession.userId == null) return;

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
                  child: FutureBuilder<List<QueryDocumentSnapshot>>(
                    future: _loadNotifications(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Erreur de chargement des notifications'),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final notifications = [...(snapshot.data ?? [])];
                      notifications.sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final bData = b.data() as Map<String, dynamic>;
                        final aDate = aData['createdAt'] as Timestamp?;
                        final bDate = bData['createdAt'] as Timestamp?;
                        return (bDate?.toDate() ?? DateTime(1970))
                            .compareTo(aDate?.toDate() ?? DateTime(1970));
                      });

                      if (notifications.isEmpty) {
                        return const Center(
                          child: Text('Aucune notification pour le moment'),
                        );
                      }

                      return ListView.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = notifications[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final title = (data['title'] ?? 'Notification').toString();
                          final body = (data['body'] ?? '').toString();
                          final isUnread = data['read'] == false;

                          return ListTile(
                            title: Text(
                              title,
                              style: TextStyle(
                                fontWeight:
                                    isUnread ? FontWeight.bold : FontWeight.normal,
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

  // ---------------------------------------------------------------------------
  // OFFRES
  // ---------------------------------------------------------------------------
  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _isLoading = true);
      try {
        final bytes = await picked.readAsBytes();
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.cloudinary.com/v1_1/demjpkcfj/image/upload'),
        );
        request.fields['upload_preset'] = 'vera2026';
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: picked.path.split('/').last,
          ),
        );
        final response = await request.send();
        final respStr = await response.stream.bytesToString();
        if (response.statusCode == 200) {
          final data = jsonDecode(respStr);
          if (data['secure_url'] != null) {
            setState(() => _logoUrl = data['secure_url']);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur upload: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _clearOfferForm() {
    _offerFormKey.currentState?.reset();
    setState(() {
      _editingOfferId = null;
      _logoUrl = null;
      _contractType = null;
      _expiryDate = null;
    });
  }

  void _editOffer(DocumentSnapshot offer) {
    final data = offer.data() as Map<String, dynamic>?;
    setState(() {
      _editingOfferId = offer.id;
      _titleController.text = data?['title'] ?? '';
      _companyController.text = data?['company'] ?? '';
      _contactEmailController.text = data?['contactEmail'] ?? '';
      _cityController.text = data?['city'] ?? '';
      _countryController.text = data?['country'] ?? '';
      _descriptionController.text = data?['description'] ?? '';
      _salaryController.text = data?['salary'] ?? '';
      _contractType = data?['contract'];
      _skillsController.text = (data?['skills'] as List?)?.join(',') ?? '';
      _expiryDate = data?['expiryDate'] != null
          ? DateTime.tryParse(data!['expiryDate'].toString())
          : null;
      _logoUrl = data?['logoUrl'] != null && data!['logoUrl'].toString().isNotEmpty
          ? data['logoUrl'].toString()
          : null;
      _showOfferForm = true;
    });
  }

  Future<void> _saveJobOffer() async {
    if (!_offerFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final payload = {
        'title': _titleController.text.trim(),
        'company': _companyController.text.trim(),
        'contactEmail': _contactEmailController.text.trim(),
        'city': _cityController.text.trim(),
        'country': _countryController.text.trim(),
        'description': _descriptionController.text.trim(),
        'salary': _salaryController.text.trim(),
        'contract': _contractType,
        'skills': _skillsController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'expiryDate': _expiryDate?.toIso8601String(),
        'logoUrl': _logoUrl,
        'userId': userSession.userId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_editingOfferId != null) {
        await firestore
            .collection('job_offers')
            .doc(_editingOfferId)
            .update(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offre mise à jour')),
          );
        }
      } else {
        await firestore.collection('job_offers').add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offre créée')),
          );
        }
      }
      _clearOfferForm();
      setState(() => _showOfferForm = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteOffer(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l\'offre'),
        content: const Text('Êtes-vous sûr de vouloir supprimer cette offre ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await firestore.collection('job_offers').doc(id).delete();
    }
  }

  Future<void> _selectExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  Widget _offerTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: type,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Color(0xFF4CAF50)),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildOfferForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _offerFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            _offerTextField(
              _titleController,
              'Titre',
              Icons.title,
              validator: (v) => v!.isEmpty ? 'Requis' : null,
            ),
            _offerTextField(_companyController, 'Entreprise', Icons.business),
            _offerTextField(
              _contactEmailController,
              'Email de contact',
              Icons.email,
              type: TextInputType.emailAddress,
            ),
            _offerTextField(_cityController, 'Ville', Icons.location_city),
            _offerTextField(_countryController, 'Pays', Icons.public),
            _offerTextField(
              _descriptionController,
              'Description',
              Icons.description,
              maxLines: 3,
            ),
            _offerTextField(
              _salaryController,
              'Salaire',
              Icons.attach_money,
              type: TextInputType.number,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                value: _contractType,
                decoration: InputDecoration(
                  labelText: 'Type de contrat',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.work_outline,
                        size: 18, color: Color(0xFF4CAF50)),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                items: _contractTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _contractType = v),
              ),
            ),
            _offerTextField(
              _skillsController,
              'Compétences (séparées par virgule)',
              Icons.code,
            ),
            InkWell(
              onTap: _selectExpiryDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: "Date d'expiration",
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.calendar_today,
                        size: 18, color: Color(0xFF4CAF50)),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: Text(
                  _expiryDate != null
                      ? '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}'
                      : 'Sélectionner une date',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _logoUrl != null && _logoUrl!.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Image.network(
                          _logoUrl!,
                          height: 80,
                          width: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 80,
                            width: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.broken_image, size: 40),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          height: 80,
                          width: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.upload, size: 40),
                        ),
                      ),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.upload),
                    label: Text(
                      _logoUrl != null && _logoUrl!.isNotEmpty
                          ? 'Logo uploadé'
                          : 'Uploader le logo',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveJobOffer,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_editingOfferId != null
                      ? 'Mettre à jour'
                      : "Ajouter l'offre"),
            ),
            if (_editingOfferId != null)
              TextButton(
                onPressed: () {
                  _clearOfferForm();
                  setState(() => _showOfferForm = false);
                },
                child: const Text('Annuler'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffersTab() {
    if (_showOfferForm) {
      return _buildOfferForm();
    }
    if (userSession.userId == null) {
      return const Center(child: Text('Non connecté'));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('job_offers')
          .where('userId', isEqualTo: userSession.userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final offers = [...snapshot.data?.docs ?? []];
        offers.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = aData['createdAt'] as Timestamp?;
          final bDate = bData['createdAt'] as Timestamp?;
          return (bDate?.toDate() ?? DateTime(1970))
              .compareTo(aDate?.toDate() ?? DateTime(1970));
        });
        if (offers.isEmpty) {
          return const Center(
            child: Text('Aucune offre. Ajoutez votre première offre.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: offers.length,
          itemBuilder: (context, index) {
            final offer = offers[index];
            final data = offer.data() as Map<String, dynamic>?;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.work, color: Color(0xFF00BCD4)),
                title: Text(data?['title'] ?? ''),
                subtitle: Text(
                  '${data?['city'] ?? ''} ${data?['country'] ?? ''}'.trim(),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _editOffer(offer),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteOffer(offer.id),
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

  // ---------------------------------------------------------------------------
  // UTILISATEURS (chercheurs d'emploi)
  // ---------------------------------------------------------------------------
  Widget _buildUsersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Rechercher un chercheur d\'emploi...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (v) => setState(() => _userSearch = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: firestore
                .collection('users')
                .where('role', isEqualTo: UserRole.employee.name)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final allUsers = snapshot.data?.docs ?? [];
              final users = allUsers.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['role'] == UserRole.employee.name;
              }).toList();
              final filtered = _userSearch.isEmpty
                  ? users
                  : users.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final email = (data['email'] ?? '').toString().toLowerCase();
                      final name = (data['name'] ?? '').toString().toLowerCase();
                      return email.contains(_userSearch) ||
                          name.contains(_userSearch);
                    }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('Aucun chercheur d\'emploi trouvé'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final user = filtered[index];
                  final data = user.data() as Map<String, dynamic>;
                  final email = data['email'] ?? 'Chercheur d\'emploi';
                  final name = data['name'] ?? '';
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF00BCD4),
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      title: Text(name.isNotEmpty ? name : email),
                      subtitle: Text(email),
                      trailing: ElevatedButton(
                        onPressed: () => _solicitJobSeeker(user.id, name.isEmpty ? email : name),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8F5E9),
                          foregroundColor: const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Sollicité',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      onTap: () =>
                          _openJobSeekerDetail(user.id, data),
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

  Future<void> _openJobSeekerDetail(String userId, Map<String, dynamic> userData) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FutureBuilder<DocumentSnapshot>(
          future: firestore.collection('jobseekers').doc(userId).get(),
          builder: (context, snapshot) {
            final profile = snapshot.data?.data() as Map<String, dynamic>?;
            final firstName = profile?['firstName'] ?? '';
            final lastName = profile?['lastName'] ?? '';
            final fullName =
                '$firstName $lastName'.trim().isNotEmpty ? '$firstName $lastName' : (userData['name'] ?? 'Chercheur d\'emploi');
            final phone = profile?['phone'] ?? '';
            final city = profile?['city'] ?? '';
            final country = profile?['country'] ?? '';
            final about = profile?['about'] ?? '';
            final skills = (profile?['languages'] as List?) ?? [];
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: const Color(0xFF00BCD4),
                          child: const Icon(Icons.person,
                              size: 40, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          userData['email'] ?? '',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      _detailRow(Icons.phone, 'Téléphone', phone),
                      _detailRow(Icons.location_city, 'Ville', city),
                      _detailRow(Icons.public, 'Pays', country),
                      if (about.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('À propos',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(about),
                      ],
                      if (skills.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Langues',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: skills
                              .map((s) => Chip(
                                  label: Text((s['name'] ?? '').toString())))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _generateCVForJobseeker(userId);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE8F5E9),
                            foregroundColor: const Color(0xFF2E7D32),
                          ),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Voir le CV'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Fermer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Color(0xFF00BCD4)),
          const SizedBox(width: 10),
          Text('$label : ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PARAMÈTRES
  // ---------------------------------------------------------------------------
  Widget _settingsField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType type = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Color(0xFF4CAF50)),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Future<void> _saveCompanyProfile() async {
    if (!_settingsFormKey.currentState!.validate()) return;
    if (userSession.userId == null) return;
    setState(() => _isLoading = true);
    try {
      await firestore.collection('users').doc(userSession.userId).set({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'website': _websiteController.text.trim(),
        'about': _aboutController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil mis à jour')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _settingsFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF00BCD4),
              child: Icon(Icons.business, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 16),
            _settingsField(_nameController, 'Nom de l\'entreprise', Icons.business),
            _settingsField(
              _phoneController,
              'Téléphone',
              Icons.phone,
              type: TextInputType.phone,
            ),
            _settingsField(
              _websiteController,
              'Site web',
              Icons.language,
              type: TextInputType.url,
            ),
            _settingsField(
              _aboutController,
              'Description de l\'entreprise',
              Icons.info,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveCompanyProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COMPATIBILITÉ (risques d'incompatibilité agrégés)
  // ---------------------------------------------------------------------------
  int _computeGlobalCompatibility(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return 0;
    const int fields = 12;
    int totalFilled = 0;
    for (final d in docs) {
      final data = d.data() as Map<String, dynamic>? ?? {};
      int filled = 0;
      if ((data['firstName'] ?? '').toString().isNotEmpty ||
          (data['lastName'] ?? '').toString().isNotEmpty) filled++;
      if ((data['phone'] ?? '').toString().isNotEmpty) filled++;
      if ((data['city'] ?? '').toString().isNotEmpty) filled++;
      if ((data['country'] ?? '').toString().isNotEmpty) filled++;
      if ((data['languages'] as List?)?.isNotEmpty ?? false) filled++;
      if ((data['diplomas'] as List?)?.isNotEmpty ?? false) filled++;
      if ((data['experienceYears'] ?? '').toString().isNotEmpty ||
          (data['experienceMonths'] ?? '').toString().isNotEmpty) filled++;
      if ((data['desiredSalary'] ?? '').toString().isNotEmpty) filled++;
      if ((data['about'] ?? '').toString().isNotEmpty) filled++;
      if ((data['skills'] as List?)?.isNotEmpty ?? false) filled++;
      if ((data['autoApply'] ?? false) == true) filled++;
      totalFilled += filled;
    }
    return ((totalFilled / (docs.length * fields)) * 100).round();
  }

  List<String> _detectRisks(List<QueryDocumentSnapshot> docs) {
    final risks = <String>[];
    if (docs.isEmpty) {
      risks.add('Aucun chercheur d\'emploi enregistré.');
      return risks;
    }
    int missingName = 0,
        missingPhone = 0,
        missingCity = 0,
        missingCountry = 0,
        missingLang = 0,
        missingDiploma = 0,
        missingExp = 0,
        missingSalary = 0,
        missingAbout = 0,
        missingSkill = 0,
        autoOff = 0;
    for (final d in docs) {
      final data = d.data() as Map<String, dynamic>? ?? {};
      if ((data['firstName'] ?? '').toString().isEmpty &&
          (data['lastName'] ?? '').toString().isEmpty) missingName++;
      if ((data['phone'] ?? '').toString().isEmpty) missingPhone++;
      if ((data['city'] ?? '').toString().isEmpty) missingCity++;
      if ((data['country'] ?? '').toString().isEmpty) missingCountry++;
      if ((data['languages'] as List?)?.isEmpty ?? true) missingLang++;
      if ((data['diplomas'] as List?)?.isEmpty ?? true) missingDiploma++;
      if ((data['experienceYears'] ?? '').toString().isEmpty &&
          (data['experienceMonths'] ?? '').toString().isEmpty) missingExp++;
      if ((data['desiredSalary'] ?? '').toString().isEmpty) missingSalary++;
      if ((data['about'] ?? '').toString().isEmpty) missingAbout++;
      if ((data['skills'] as List?)?.isEmpty ?? true) missingSkill++;
      if ((data['autoApply'] ?? false) != true) autoOff++;
    }
    void addIf(int count, String label) {
      if (count > 0) risks.add('$count profil(s) : $label');
    }

    addIf(missingName, 'nom/prénom manquant');
    addIf(missingPhone, 'téléphone non renseigné');
    addIf(missingCity, 'ville non renseignée');
    addIf(missingCountry, 'pays non renseigné');
    addIf(missingLang, 'aucune langue renseignée');
    addIf(missingDiploma, 'aucun diplôme renseigné');
    addIf(missingExp, 'expérience non renseignée');
    addIf(missingSalary, 'salaire souhaité non renseigné');
    addIf(missingAbout, 'section « à propos » vide');
    addIf(missingSkill, 'compétences non renseignées');
    addIf(autoOff, 'candidature automatique désactivée');
    return risks;
  }

  Widget _buildGlobalCompatibility() {
    if (_jobseekersStream == null) {
      return const Center(child: Text('Non connecté'));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: _jobseekersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final score = _computeGlobalCompatibility(docs);
        final risks = _detectRisks(docs);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        height: 110,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: score / 100,
                              strokeWidth: 10,
                              backgroundColor: Colors.grey[300],
                              color: const Color(0xFF00BCD4),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$score%',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'compatibilité',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Score global de compatibilité',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Calculé sur ${docs.length} chercheur(s) d\'emploi',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Basé sur la complétude des profils et l\'activation '
                              'de la candidature automatique.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Risques d\'incompatibilité détectés',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (risks.isEmpty)
                        const Text(
                          'Aucun risque détecté. Les profils sont bien renseignés.',
                          style: TextStyle(color: Colors.green),
                        )
                      else
                        ...risks.map(
                          (r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_amber,
                                    color: Colors.orange, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(r)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendPushNotification(String token, String title, String body) async {
    try {
      await http.post(
        Uri.parse('http://192.168.189.89/VERA/send_notification.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'title': title,
          'body': body,
        }),
      );
    } catch (e) {}
  }

  Future<void> _solicitJobSeeker(String userId, String userName) async {
    if (userSession.userId == null) return;
    setState(() => _isLoading = true);
    try {
      final companyName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'Entreprise';

      await firestore.collection('solicitations').add({
        'companyId': userSession.userId,
        'jobseekerId': userId,
        'companyName': companyName,
        'jobseekerName': userName,
        'status': 'sent',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await firestore.collection('jobseeker_notifications').add({
        'userId': userId,
        'title': 'Nouvelle sollicitation',
        'body': '$companyName est intéressé par votre profil.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final userDoc = await firestore.collection('users').doc(userId).get();
      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _sendPushNotification(
          fcmToken,
          'Nouvelle sollicitation',
          '$companyName est intéressé par votre profil.',
        );
      }

      final participants = [userSession.userId, userId]..sort();
      final conversationId = participants.join('_');
      final conversationRef = firestore.collection('messages').doc(conversationId);
      final existing = await conversationRef.get();
      if (!existing.exists) {
        await conversationRef.set({
          'participants': participants,
          'lastMessage': 'Nouvelle sollicitation: $companyName est intéressé par votre profil',
          'senderName': companyName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sollicitation envoyée')),
        );
      }

      await _generateCVForJobseeker(userId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  pw.Widget _buildPdfSection({required String title, required List<pw.Widget> children}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColor(0.91, 0.96, 0.93),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor(0.3, 0.69, 0.31),
            ),
          ),
          pw.Divider(color: PdfColor(0.3, 0.69, 0.31), thickness: 1, height: 12),
          ...children,
        ],
      ),
    );
  }

  pw.Widget _buildPdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value.isEmpty ? '-' : value, style: pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _generateCVForJobseeker(String userId) async {
    setState(() => _isLoading = true);
    bool loadingDismissed = false;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => WillPopScope(
          onWillPop: () async => false,
          child: const Dialog(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 24),
                  Text('Génération du CV...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final userDoc = await firestore.collection('users').doc(userId).get();
      final profileDoc = await firestore.collection('jobseekers').doc(userId).get();

      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      final profileData = profileDoc.data() as Map<String, dynamic>? ?? {};

      final name = '${profileData['firstName'] ?? ''} ${profileData['lastName'] ?? ''}'.trim();
      final email = userData['email'] ?? profileData['email'] ?? '';
      final phone = profileData['phone'] ?? '';
      final city = profileData['city'] ?? '';
      final country = profileData['country'] ?? '';
      final about = profileData['about'] ?? '';
      final languages = (profileData['languages'] as List?)?.map((l) => l['name'] ?? '').join(', ') ?? '';
      final experienceYears = profileData['experienceYears'] ?? '';
      final experienceMonths = profileData['experienceMonths'] ?? '';
      final currentPosition = profileData['currentPosition'] ?? '';
      final currentSalary = profileData['currentSalary'] ?? '';
      final contractType = profileData['contractType'] ?? 'Non renseigné';
      final availability = profileData['availability'] ?? '';
      final desiredSalary = profileData['desiredSalary'] ?? '';
      final workMode = profileData['workMode'] ?? 'Non renseigné';
      final diplomas = (profileData['diplomas'] as List?)?.map((d) {
        final name = d['name'] ?? '';
        final date = d['date'] ?? '';
        final school = d['school'] ?? '';
        final parts = [name];
        if (date.isNotEmpty) parts.add('($date)');
        if (school.isNotEmpty) parts.add('- $school');
        return parts.join(' ');
      }).join('\n') ?? 'Aucun diplôme renseigné';

      final pdf = pw.Document();

      pw.MemoryImage? profileImage;
      final photoUrl = profileData['profilePhotoUrl'] ?? userData['profilePhotoUrl'];
      if (photoUrl != null && photoUrl.toString().isNotEmpty) {
        try {
          final response = await http.get(Uri.parse(photoUrl.toString()));
          if (response.statusCode == 200) {
            profileImage = pw.MemoryImage(response.bodyBytes);
          }
        } catch (e) {}
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (profileImage != null)
                      pw.Container(
                        width: 90,
                        height: 90,
                        decoration: const pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                        ),
                        child: pw.ClipOval(
                          child: pw.Image(profileImage, width: 90, height: 90, fit: pw.BoxFit.cover),
                        ),
                      )
                    else
                      pw.Container(
                        width: 90,
                        height: 90,
                        decoration: const pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          color: PdfColor(0.9, 0.9, 0.9),
                        ),
                        child: pw.Center(
                          child: pw.Text('?', style: pw.TextStyle(fontSize: 32, color: PdfColor(0.5, 0.5, 0.5))),
                        ),
                      ),
                    pw.SizedBox(width: 24),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            name.isEmpty ? 'Candidat' : name,
                            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColor(0.13, 0.13, 0.13)),
                          ),
                          if (email.isNotEmpty) pw.Text(email, style: pw.TextStyle(fontSize: 12, color: PdfColor(0.46, 0.46, 0.46))),
                          if (phone.isNotEmpty) pw.Text(phone, style: pw.TextStyle(fontSize: 12, color: PdfColor(0.46, 0.46, 0.46))),
                          if (city.isNotEmpty || country.isNotEmpty)
                            pw.Text('$city, $country', style: pw.TextStyle(fontSize: 12, color: PdfColor(0.46, 0.46, 0.46))),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Divider(color: PdfColor(0.3, 0.69, 0.31), thickness: 2),
                pw.SizedBox(height: 16),
                _buildPdfSection(title: 'INFORMATIONS PERSONNELLES', children: [
                  _buildPdfRow('Email', email),
                  _buildPdfRow('Téléphone', phone),
                  _buildPdfRow('Localisation', '$city, $country'),
                ]),
                _buildPdfSection(title: 'EXPÉRIENCE PROFESSIONNELLE', children: [
                  if (currentPosition.isNotEmpty) _buildPdfRow('Poste actuel', currentPosition),
                  _buildPdfRow('Expérience', '$experienceYears ans, $experienceMonths mois'),
                  if (currentSalary.isNotEmpty) _buildPdfRow('Salaire actuel', currentSalary),
                  _buildPdfRow('Type de contrat', contractType),
                  if (availability.isNotEmpty) _buildPdfRow('Disponibilité', availability),
                ]),
                _buildPdfSection(title: 'FORMATIONS & DIPLÔMES', children: [
                  if (diplomas.isNotEmpty && diplomas != 'Aucun diplôme renseigné')
                    pw.Text(diplomas, style: pw.TextStyle(fontSize: 11))
                  else
                    pw.Text('Aucun diplôme renseigné', style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic)),
                ]),
                _buildPdfSection(title: 'LANGUES & LOISIRS', children: [
                  if (languages.isNotEmpty) _buildPdfRow('Langues', languages),
                ]),
                _buildPdfSection(title: 'PRÉFÉRENCES', children: [
                  if (desiredSalary.isNotEmpty) _buildPdfRow('Salaire souhaité', desiredSalary),
                  _buildPdfRow('Mode de travail', workMode),
                ]),
                if (about.isNotEmpty)
                  _buildPdfSection(title: 'À PROPOS', children: [
                    pw.Text(about, style: pw.TextStyle(fontSize: 11)),
                  ]),
              ],
            );
          },
        ),
      );

      final fcmToken = userData['fcmToken'] as String?;
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _sendPushNotification(
          fcmToken,
          'CV consulté',
          'Votre CV a été consulté par une entreprise.',
        );
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingDismissed = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            insetPadding: EdgeInsets.zero,
            child: Column(
              children: [
                Expanded(
                  child: PdfPreview(
                    build: (PdfPageFormat format) => pdf.save(),
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final bytes = await pdf.save();
                            Printing.sharePdf(
                              bytes: bytes,
                              filename: 'cv_${name.replaceAll(' ', '_').toLowerCase()}.pdf',
                            );
                          },
                          icon: const Icon(Icons.share),
                          label: const Text('Partager PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00BCD4),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            final participants = [userSession.userId, userId]..sort();
                            final conversationId = participants.join('_');
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                  conversationId: conversationId,
                                  otherUserId: userId,
                                  otherUserName: name,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE8F5E9),
                            foregroundColor: const Color(0xFF2E7D32),
                          ),
                          child: const Text('Discuter avec l\'utilisateur'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[200],
                            foregroundColor: Colors.black87,
                          ),
                          child: const Text('Annuler'),
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
    } catch (e) {
      if (mounted) {
        if (!loadingDismissed) {
          Navigator.of(context, rootNavigator: true).pop();
          loadingDismissed = true;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur génération CV: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        if (!loadingDismissed) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildMessagesView() {
    if (userSession.userId == null) {
      return const Center(child: Text('Non connecté'));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('messages')
          .where('participants', arrayContains: userSession.userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data?.docs ?? [];
        if (messages.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('Aucun message', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: messages.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
          itemBuilder: (context, index) {
            final data = messages[index].data() as Map<String, dynamic>;
            final conversation = messages[index];
            final participants = List<String>.from(data['participants'] ?? []);
            final otherUserId = participants.firstWhere(
              (id) => id != userSession.userId,
              orElse: () => '',
            );
            final lastMessage = data['lastMessage'] ?? 'Message';
            final createdAt = data['createdAt'] as Timestamp?;
            final isOnline = data['isOnline'] == true;

            if (otherUserId.isEmpty) {
              return const SizedBox.shrink();
            }

            return StreamBuilder<DocumentSnapshot>(
              stream: firestore.collection('users').doc(otherUserId).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.hasError) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: const Text('Utilisateur', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                  );
                }
                if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: const Text('Utilisateur', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                  );
                }
                final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                final otherUserName =
                    (userData['name'] ?? userData['email'] ?? 'Utilisateur').toString();
                final otherUserEmail = (userData['email'] ?? '').toString();

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF00BCD4),
                    child: Text(
                      otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    otherUserName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (createdAt != null)
                        Text(
                          '${createdAt.toDate().hour.toString().padLeft(2, '0')}:${createdAt.toDate().minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      if (isOnline) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          conversationId: conversation.id,
                          otherUserId: otherUserId,
                          otherUserName: otherUserName,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildApplicationsView() {
    if (userSession.userId == null) {
      return const Center(child: Text('Non connecté'));
    }
    if (_applicationsStream == null) {
      return const Center(child: Text('Aucune candidature reçue'));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: _applicationsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final applications = [...snapshot.data?.docs ?? []];
        applications.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = (aData['appliedAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
          final bDate = (bData['appliedAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
          return bDate.compareTo(aDate);
        });
        if (applications.isEmpty) {
          return const Center(child: Text('Aucune candidature reçue'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: applications.length,
          itemBuilder: (context, index) {
            final data = applications[index].data() as Map<String, dynamic>;
            final status = (data['status'] ?? 'pending').toString();
            final applicationId = applications[index].id;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: ListTile(
                title: Text(data['offerTitle'] ?? 'Offre inconnue'),
                subtitle: Text('Candidat: ${data['userName'] ?? 'Anonyme'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status != 'accepted')
                      ElevatedButton(
                        onPressed: () async {
                          await firestore
                              .collection('applications')
                              .doc(applicationId)
                              .update({'status': 'accepted'});
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Candidature acceptée')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8F5E9),
                          foregroundColor: const Color(0xFF2E7D32),
                        ),
                        child: const Text('Accepter'),
                      ),
                    if (status == 'accepted')
                      const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDemandsView() {
    if (userSession.userId == null) {
      return const Center(child: Text('Non connecté'));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('job_offers')
          .where('userId', isEqualTo: userSession.userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final offers = snapshot.data?.docs ?? [];
        if (offers.isEmpty) {
          return const Center(
            child: Text('Aucune offre publiée'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: offers.length,
          itemBuilder: (context, index) {
            final offer = offers[index];
            final offerData = offer.data() as Map<String, dynamic>;
            final offerId = offer.id;
            final offerTitle = offerData['title'] ?? 'Offre sans titre';

            return StreamBuilder<QuerySnapshot>(
              stream: firestore
                  .collection('applications')
                  .where('offerId', isEqualTo: offerId)
                  .snapshots(),
              builder: (context, appSnapshot) {
                final applications = appSnapshot.data?.docs ?? [];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: ExpansionTile(
                    title: Text(
                      offerTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${applications.length} candidature(s)',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    children: [
                      if (applications.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Aucune candidature pour le moment',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ...applications.map((app) {
                          final appData = app.data() as Map<String, dynamic>;
                          final status = (appData['status'] ?? 'pending').toString();
                          final userName = appData['userName'] ?? 'Candidat';
                          final applicationId = app.id;
                          return ListTile(
                            title: Text(userName),
                            subtitle: Text(
                              'Statut: ${_formatStatus(status)}',
                              style: TextStyle(
                                color: _statusColor(status),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (status != 'accepted' && status != 'rejected')
                                  IconButton(
                                    onPressed: () async {
                                      await firestore
                                          .collection('applications')
                                          .doc(applicationId)
                                          .update({'status': 'accepted'});
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Candidature acceptée')),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.check_circle, color: Colors.green),
                                    tooltip: 'Accepter',
                                  ),
                                if (status != 'rejected')
                                  IconButton(
                                    onPressed: () async {
                                      await firestore
                                          .collection('applications')
                                          .doc(applicationId)
                                          .update({'status': 'rejected'});
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Candidature refusée')),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.cancel, color: Colors.red),
                                    tooltip: 'Refuser',
                                  ),
                                if (status == 'accepted')
                                  const Icon(Icons.verified, color: Colors.green, size: 20),
                                if (status == 'rejected')
                                  const Icon(Icons.block, color: Colors.red, size: 20),
                              ],
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return 'Acceptée';
      case 'rejected':
        return 'Refusée';
      case 'pending':
        return 'En attente';
      case 'sent':
        return 'Envoyée';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'sent':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildSolicitationsTab() {
    if (userSession.userId == null) {
      return const Center(child: Text('Non connecté'));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: _solicitationsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final solicitations = List.from(docs);
        solicitations.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = (aData['createdAt'] as Timestamp?)?.toDate();
          final bDate = (bData['createdAt'] as Timestamp?)?.toDate();
          return (bDate ?? DateTime(1970)).compareTo(aDate ?? DateTime(1970));
        });
        if (solicitations.isEmpty) {
          return const Center(
            child: Text('Aucune sollicitation envoyée'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: solicitations.length,
          itemBuilder: (context, index) {
            final solicitation = solicitations[index];
            final data = solicitation.data() as Map<String, dynamic>;
            final jobseekerId = data['jobseekerId'] ?? '';
            final jobseekerName = data['jobseekerName'] ?? 'Chercheur d\'emploi';
            final createdAt = data['createdAt'] as Timestamp?;
            final dateStr = createdAt != null
                ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
                : '';
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF00BCD4),
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: Text(jobseekerName),
                subtitle: Text(dateStr.isNotEmpty ? 'Sollicité le $dateStr' : ''),
                trailing: ElevatedButton(
                  onPressed: () => _generateCVForJobseeker(jobseekerId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8F5E9),
                    foregroundColor: const Color(0xFF2E7D32),
                  ),
                  child: const Text('Voir CV'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
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
            tooltip: 'Déconnexion',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Déconnexion'),
                  content:
                      const Text('Voulez-vous vraiment vous déconnecter ?'),
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
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildUsersTab(),
          _buildOffersTab(),
          _buildDemandsView(),
          _buildMessagesView(),
          _buildSolicitationsTab(),
          _buildApplicationsView(),
        ],
      ),
      floatingActionButton: _currentIndex == 1 && !_showOfferForm
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF00BCD4),
              foregroundColor: Colors.white,
              onPressed: () {
                _clearOfferForm();
                setState(() => _showOfferForm = true);
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF00BCD4),
        unselectedItemColor: Colors.black,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Utilisateurs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.work),
            label: 'Offres',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Demandes',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat),
                if (_unreadMessageCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        _unreadMessageCount > 99 ? '99+' : '$_unreadMessageCount',
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
            ),
            label: 'Messagerie',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mark_email_read),
            label: 'Candidatures',
          ),
        ],
      ),
    );
  }
}
