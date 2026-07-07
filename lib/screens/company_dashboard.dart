import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../auth_service.dart';

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

  int _currentIndex = 0;

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
            .orderBy('createdAt', descending: true)
            .limit(10)
            .snapshots()
        : null;
    _initNotifications();
    _saveFcmToken();
    _loadCompanyProfile();
    _jobseekersStream = firestore.collection('jobseekers').snapshots();
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
        final unreadCount = snapshot.data?.docs
                .where((doc) =>
                    (doc.data() as Map<String, dynamic>)['read'] == false)
                .length ??
            0;
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
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
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
                      trailing: const Icon(Icons.chevron_right),
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
          _buildSettingsTab(),
          _buildGlobalCompatibility(),
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
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Utilisateurs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.work),
            label: 'Offres',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Paramètres',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights),
            label: 'Compatibilité',
          ),
        ],
      ),
    );
  }
}
