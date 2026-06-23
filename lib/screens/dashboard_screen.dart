import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:share_plus/share_plus.dart';
import '../auth_service.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    switch (userSession.role) {
      case UserRole.admin:
        return const AdminDashboard();
      case UserRole.employee:
        return const EmployeeDashboard();
      case UserRole.company:
        return const CompanyDashboard();
      default:
        return const EmployeeDashboard();
    }
  }
}

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  bool _isLoading = false;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final _personalFormKey = GlobalKey<FormState>();
  final _familyFormKey = GlobalKey<FormState>();
  final _experienceFormKey = GlobalKey<FormState>();
  final _preferencesFormKey = GlobalKey<FormState>();
  final _aboutFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _countryController = TextEditingController();
  final _cityController = TextEditingController();
  String? _profilePhotoUrl;

  final _maritalStatusController = TextEditingController();
  final _childrenCountController = TextEditingController();

  final List<String> _maritalStatusOptions = [
    'Célibataire',
    'Marié(e)',
    'Divorcé(e)',
    'Veuf(ve)',
  ];
  String? _selectedMaritalStatus;

  final List<Map<String, dynamic>> _languages = [];
  final List<Map<String, dynamic>> _hobbies = [];
  final _languageController = TextEditingController();
  final TextEditingController _hobbyController = TextEditingController();

  final _currentSalaryController = TextEditingController();
  final _experienceMonthsController = TextEditingController();
  final _experienceYearsController = TextEditingController();
  bool _isCurrentlyWorking = false;
  final _currentPositionController = TextEditingController();
  final _contractTypeController = TextEditingController();
  final List<String> _contractTypes = [
    'CDI',
    'CDD',
    'Temps partiel',
    'Freelance',
    'Stage',
    'Intérim',
  ];
  String? _selectedContractType;

  final _availabilityController = TextEditingController();
  final _desiredSalaryController = TextEditingController();
  final List<String> _workModes = ['Présentiel', 'Télétravail', 'Hybride'];
  String? _selectedWorkMode;

  final _aboutController = TextEditingController();

  int _currentIndex = 0;
  int _profilePageIndex = 0;
  final List<String> _diplomas = [];
  String _searchQuery = '';
  Map<String, dynamic>? _selectedOffer;
  bool _autoApplyEnabled = false;
  final Set<String> _appliedOfferIds = {};
  final Set<String> _pendingAutoApplyOfferIds = {};
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _initNotifications();
    _loadAppliedOffers();
  }

  Future<void> _loadAppliedOffers() async {
    if (userSession.userId == null) return;
    try {
      final snapshot = await firestore
          .collection('applications')
          .where('userId', isEqualTo: userSession.userId)
          .get();
      setState(() {
        _appliedOfferIds.addAll(snapshot.docs.map((d) => d.data()['offerId'] as String));
      });
    } catch (e) {}
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'vera_channel',
      'VERA Notifications',
      channelDescription: 'Notifications de candidatures',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notificationsPlugin.show(0, title, body, details);
  }

  Future<void> _saveUserNotification({
    required String title,
    required String body,
    required String offerId,
    required String offerTitle,
    required bool automatic,
  }) async {
    if (userSession.userId == null) return;
    await firestore.collection('jobseeker_notifications').add({
      'userId': userSession.userId,
      'title': title,
      'body': body,
      'offerId': offerId,
      'offerTitle': offerTitle,
      'automatic': automatic,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _markNotificationsAsRead() async {
    if (userSession.userId == null) return;
    final snapshot = await firestore
        .collection('jobseeker_notifications')
        .where('userId', isEqualTo: userSession.userId)
        .get();
    final batch = firestore.batch();
    var hasUpdates = false;
    for (final doc in snapshot.docs) {
      if (doc.data()['read'] == false) {
        batch.update(doc.reference, {'read': true});
        hasUpdates = true;
      }
    }
    if (hasUpdates) {
      await batch.commit();
    }
  }

  Future<void> _applyToOffer([QueryDocumentSnapshot? offer, bool automatic = false]) async {
    String offerId;
    String offerTitle;
    String contactEmail = '';

    if (offer != null) {
      offerId = offer.id;
      final data = offer.data() as Map<String, dynamic>;
      offerTitle = data['title'] ?? '';
      contactEmail = _extractOfferEmail(data);
    } else if (_selectedOffer != null) {
      offerId = _selectedOffer!['id'] ?? '';
      offerTitle = _selectedOffer!['title'] ?? '';
      contactEmail = _extractOfferEmail(_selectedOffer!);
    } else {
      return;
    }

    if (_appliedOfferIds.contains(offerId)) return;

    setState(() => _isLoading = true);
    try {
      if (offerId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de postuler à cette offre')),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      final idToken = await auth.currentUser?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Utilisateur non authentifié')),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      // Sauvegarder la candidature dans Firestore
      final applicationRef = firestore
          .collection('applications')
          .doc('${userSession.userId}_$offerId${DateTime.now().millisecondsSinceEpoch}');
      await applicationRef.set({
        'userId': userSession.userId,
        'offerId': offerId,
        'offerTitle': offerTitle,
        'userName': '${_firstNameController.text} ${_lastNameController.text}',
        'userEmail': _emailController.text,
        'contactEmail': contactEmail,
        'status': contactEmail.isNotEmpty ? 'sent' : 'pending',
        'appliedAt': FieldValue.serverTimestamp(),
      });

      final response = await http.post(
        Uri.parse('http://192.168.189.89/VERA/apply.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'offerId': offerId,
          'userId': userSession.userId,
          'idToken': idToken,
          'firstName': _firstNameController.text,
          'lastName': _lastNameController.text,
          'email': _emailController.text,
          'phone': _phoneController.text,
          'city': _cityController.text,
          'country': _countryController.text,
          'about': _aboutController.text,
          'desiredSalary': _desiredSalaryController.text,
          'workMode': _selectedWorkMode ?? '',
          'experienceYears': _experienceYearsController.text,
          'experienceMonths': _experienceMonthsController.text,
          'diplomas': _diplomas,
          'title': offerTitle,
          'contactEmail': contactEmail,
        }),
      );

      if (response.statusCode != 200) {
        if (automatic) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur serveur - offre ignorée')),
            );
          }
        }
        setState(() => _appliedOfferIds.add(offerId));
        return;
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _appliedOfferIds.add(offerId));
        if (mounted) {
          final notificationTitle =
              automatic ? 'Candidature automatique envoyee' : 'Candidature envoyee';
          final notificationBody = automatic
              ? 'Vous avez postule automatiquement a $offerTitle'
              : 'Vous avez postule a $offerTitle';
          try {
            await _saveUserNotification(
              title: notificationTitle,
              body: notificationBody,
              offerId: offerId,
              offerTitle: offerTitle,
              automatic: automatic,
            );
          } catch (e) {}
          await _showNotification(
            notificationTitle,
            notificationBody,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Candidature envoyée')),
          );
          if (offer == null) {
            setState(() => _selectedOffer = null);
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Erreur lors de la candidature')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (automatic) {
        _pendingAutoApplyOfferIds.remove(offerId);
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProfileData() async {
    if (userSession.userId == null) return;
    try {
      final doc = await firestore
          .collection('jobseekers')
          .doc(userSession.userId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _firstNameController.text = data['firstName'] ?? '';
          _lastNameController.text = data['lastName'] ?? '';
          _emailController.text = data['email'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _countryController.text = data['country'] ?? '';
          _cityController.text = data['city'] ?? '';
          _selectedMaritalStatus = data['maritalStatus'];
          _childrenCountController.text = data['childrenCount'] ?? '';
          if (data['languages'] != null) {
            _languages.clear();
            _languages.addAll(
              List<Map<String, dynamic>>.from(
                (data['languages'] as List).map(
                  (e) => Map<String, dynamic>.from(e),
                ),
              ),
            );
          }
          if (data['hobbies'] != null) {
            _hobbies.clear();
            _hobbies.addAll(
              List<Map<String, dynamic>>.from(
                (data['hobbies'] as List).map(
                  (e) => Map<String, dynamic>.from(e),
                ),
              ),
            );
          }
          _currentSalaryController.text = data['currentSalary'] ?? '';
          _experienceMonthsController.text = data['experienceMonths'] ?? '';
          _experienceYearsController.text = data['experienceYears'] ?? '';
          _isCurrentlyWorking = data['isCurrentlyWorking'] ?? false;
          _currentPositionController.text = data['currentPosition'] ?? '';
          _selectedContractType = data['contractType'];
          _availabilityController.text = data['availability'] ?? '';
          _desiredSalaryController.text = data['desiredSalary'] ?? '';
          _selectedWorkMode = data['workMode'];
          _aboutController.text = data['about'] ?? '';
          if (data['diplomas'] != null) {
            _diplomas.clear();
            _diplomas.addAll(List<String>.from(data['diplomas']));
          }
          _profilePhotoUrl = data['profilePhotoUrl'];
          _autoApplyEnabled = data['autoApply'] ?? false;
        });
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    _cityController.dispose();
    _maritalStatusController.dispose();
    _childrenCountController.dispose();
    _languageController.dispose();
    _hobbyController.dispose();
    _currentSalaryController.dispose();
    _experienceMonthsController.dispose();
    _experienceYearsController.dispose();
    _currentPositionController.dispose();
    _contractTypeController.dispose();
    _availabilityController.dispose();
    _desiredSalaryController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  void _logout() async {
    setState(() => _isLoading = true);
    await userSession.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Future<void> _pickProfilePhoto() async {
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
            setState(() {
              _profilePhotoUrl = data['secure_url'];
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Photo de profil mise à jour')),
              );
              _saveProfilePhoto();
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString()}')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfilePhoto() async {
    if (_profilePhotoUrl == null) return;
    try {
      await firestore
          .collection('jobseekers')
          .doc(userSession.userId ?? '')
          .set({'profilePhotoUrl': _profilePhotoUrl}, SetOptions(merge: true));
    } catch (e) {}
  }

  Future<void> _generateCV() async {
    final name = '${_firstNameController.text} ${_lastNameController.text}'.trim();
    final email = _emailController.text;
    final phone = _phoneController.text;
    final city = _cityController.text;
    final country = _countryController.text;
    final maritalStatus = _selectedMaritalStatus ?? 'Non renseigné';
    final childrenCount = _childrenCountController.text.isEmpty ? '0' : _childrenCountController.text;
    final experienceYears = _experienceYearsController.text;
    final experienceMonths = _experienceMonthsController.text;
    final currentPosition = _currentPositionController.text;
    final currentSalary = _currentSalaryController.text;
    final contractType = _selectedContractType ?? 'Non renseigné';
    final availability = _availabilityController.text;
    final desiredSalary = _desiredSalaryController.text;
    final workMode = _selectedWorkMode ?? 'Non renseigné';
    final about = _aboutController.text;
    final languages = _languages.map((l) => l['name'] ?? '').join(', ');
    final hobbies = _hobbies.map((h) => h['name'] ?? '').join(', ');
    final diplomas = _diplomas.join('\n');

    final cvContent = StringBuffer();
    cvContent.writeln('CURRICULUM VITAE');
    cvContent.writeln('================');
    cvContent.writeln();
    cvContent.writeln('INFORMATIONS PERSONNELLES');
    cvContent.writeln('Nom: $name');
    if (email.isNotEmpty) cvContent.writeln('Email: $email');
    if (phone.isNotEmpty) cvContent.writeln('Téléphone: $phone');
    if (city.isNotEmpty) cvContent.writeln('Ville: $city');
    if (country.isNotEmpty) cvContent.writeln('Pays: $country');
    cvContent.writeln('Situation familiale: $maritalStatus');
    cvContent.writeln('Enfants: $childrenCount');
    cvContent.writeln();
    cvContent.writeln('EXPÉRIENCE PROFESSIONNELLE');
    if (currentPosition.isNotEmpty) cvContent.writeln('Poste actuel: $currentPosition');
    cvContent.writeln('Expérience: $experienceYears ans, $experienceMonths mois');
    if (currentSalary.isNotEmpty) cvContent.writeln('Salaire actuel: $currentSalary');
    cvContent.writeln('Type de contrat: $contractType');
    if (availability.isNotEmpty) cvContent.writeln('Disponibilité: $availability');
    cvContent.writeln();
    cvContent.writeln('PRÉFÉRENCES');
    if (desiredSalary.isNotEmpty) cvContent.writeln('Salaire souhaité: $desiredSalary');
    cvContent.writeln('Mode de travail: $workMode');
    cvContent.writeln();
    cvContent.writeln('FORMATIONS & DIPLÔMES');
    if (diplomas.isNotEmpty) cvContent.writeln(diplomas);
    cvContent.writeln();
    cvContent.writeln('COMPÉTENCES');
    if (languages.isNotEmpty) cvContent.writeln('Langues: $languages');
    if (hobbies.isNotEmpty) cvContent.writeln('Loisirs: $hobbies');
    cvContent.writeln();
    cvContent.writeln('À PROPOS');
    if (about.isNotEmpty) cvContent.writeln(about);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mon CV'),
          content: SingleChildScrollView(
            child: SelectableText(
              cvContent.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Share.share(cvContent.toString(), subject: 'Mon CV - $name');
              },
              icon: const Icon(Icons.share),
              label: const Text('Partager'),
            ),
          ],
        ),
      );
    }
  }

  int _calculateProfileSectionCompletion() {
    int total = 0;
    int filled = 0;
    switch (_profilePageIndex) {
      case 1:
        total += 5;
        if (_selectedMaritalStatus != null) filled++;
        total += 5;
        if (_childrenCountController.text.isNotEmpty) filled++;
        break;
      case 2:
        total += 10;
        if (_diplomas.isNotEmpty) filled++;
        break;
      case 3:
        total += 10;
        if (_currentSalaryController.text.isNotEmpty) filled++;
        total += 10;
        if (_experienceMonthsController.text.isNotEmpty) filled++;
        total += 10;
        if (_experienceYearsController.text.isNotEmpty) filled++;
        total += 10;
        if (_isCurrentlyWorking && _currentPositionController.text.isNotEmpty)
          filled++;
        total += 10;
        if (_isCurrentlyWorking && _selectedContractType != null) filled++;
        break;
      case 4:
        total += 10;
        if (_languages.isNotEmpty) filled++;
        total += 10;
        if (_hobbies.isNotEmpty) filled++;
        break;
      case 5:
        total += 10;
        if (_availabilityController.text.isNotEmpty) filled++;
        total += 10;
        if (_desiredSalaryController.text.isNotEmpty) filled++;
        total += 10;
        if (_selectedWorkMode != null) filled++;
        break;
      case 6:
        total += 10;
        if (_aboutController.text.isNotEmpty) filled++;
        break;
    }
    return total > 0 ? ((filled / total) * 100).round() : 0;
  }

  int _calculateProfileCompletion() {
    int total = 0;
    int filled = 0;
    total += 5;
    if (_firstNameController.text.isNotEmpty) filled++;
    total += 5;
    if (_lastNameController.text.isNotEmpty) filled++;
    total += 5;
    if (_emailController.text.isNotEmpty) filled++;
    total += 5;
    if (_phoneController.text.isNotEmpty) filled++;
    total += 5;
    if (_countryController.text.isNotEmpty) filled++;
    total += 5;
    if (_cityController.text.isNotEmpty) filled++;
    total += 5;
    if (_selectedMaritalStatus != null) filled++;
    total += 5;
    if (_childrenCountController.text.isNotEmpty) filled++;
    total += 10;
    if (_languages.isNotEmpty) filled++;
    total += 10;
    if (_hobbies.isNotEmpty) filled++;
    total += 10;
    if (_experienceMonthsController.text.isNotEmpty) filled++;
    total += 10;
    if (_experienceYearsController.text.isNotEmpty) filled++;
    total += 10;
    if (_currentPositionController.text.isNotEmpty) filled++;
    total += 10;
    if (_selectedContractType != null) filled++;
    total += 10;
    if (_availabilityController.text.isNotEmpty) filled++;
    total += 10;
    if (_selectedWorkMode != null) filled++;
    total += 10;
    if (_aboutController.text.isNotEmpty) filled++;
    total += 10;
    if (_diplomas.isNotEmpty) filled++;
    return ((filled / total) * 100).round();
  }

  String _getProfileSectionTitle() {
    switch (_profilePageIndex) {
      case 0:
        return 'Informations personnelles';
      case 1:
        return 'Situation familiale';
      case 2:
        return 'Situation familiale';
      case 2:
        return 'Formations & Diplômes';
      case 3:
        return 'Expérience professionnelle';
      case 4:
        return 'Langues & Loisirs';
      case 5:
        return 'Préférences';
      case 6:
        return 'À propos';
      default:
        return 'Mon Profil';
    }
  }

  Future<void> _saveProfile(String section) async {
    setState(() => _isLoading = true);
    try {
      final profileData = {
        'firstName': _firstNameController.text,
        'lastName': _lastNameController.text,
        'email': _emailController.text,
        'phone': _phoneController.text,
        'country': _countryController.text,
        'city': _cityController.text,
        'maritalStatus': _selectedMaritalStatus,
        'childrenCount': _childrenCountController.text,
        'languages': _languages,
        'hobbies': _hobbies,
        'isCurrentlyWorking': _isCurrentlyWorking,
        'currentPosition': _currentPositionController.text,
        'currentSalary': _currentSalaryController.text,
        'contractType': _selectedContractType,
        'experienceMonths': _experienceMonthsController.text,
        'experienceYears': _experienceYearsController.text,
        'availability': _availabilityController.text,
        'desiredSalary': _desiredSalaryController.text,
        'workMode': _selectedWorkMode,
        'about': _aboutController.text,
        'diplomas': _diplomas,
        'autoApply': _autoApplyEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await firestore
          .collection('jobseekers')
          .doc(userSession.userId ?? '')
          .set(profileData, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil sauvegardé avec succès')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addLanguage() {
    if (_languageController.text.isNotEmpty) {
      setState(() {
        _languages.add({'name': _languageController.text});
        _languageController.clear();
      });
    }
  }

  void _removeLanguage(int index) {
    setState(() => _languages.removeAt(index));
  }

  void _addHobby() {
    if (_hobbyController.text.isNotEmpty) {
      setState(() {
        _hobbies.add({'name': _hobbyController.text});
        _hobbyController.clear();
      });
    }
  }

  void _removeHobby(int index) {
    setState(() => _hobbies.removeAt(index));
  }

  Future<void> _pickDiploma() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _isLoading = true);
      try {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.cloudinary.com/v1_1/demjpkcfj/upload'),
        );
        request.fields['upload_preset'] = 'vera2026';
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: result.files.single.name,
          ),
        );
        final response = await request.send();
        final respStr = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          final data = jsonDecode(respStr);
          if (data['secure_url'] != null) {
            setState(() {
              _diplomas.add(data['secure_url']);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Diplôme uploadé avec succès')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erreur upload: Code ${response.statusCode}'),
              ),
            );
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

  Widget _buildProfileHeader() {
    return Container(
      decoration: const BoxDecoration(color: Colors.white),
      child: SafeArea(
        left: true,
        top: true,
        right: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      GestureDetector(
                        onTap: _pickProfilePhoto,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundImage: _profilePhotoUrl != null
                              ? CachedNetworkImageProvider(_profilePhotoUrl!)
                              : null,
                          backgroundColor: Colors.white,
                          child: _profilePhotoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Color(0xFF4CAF50),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_firstNameController.text.isEmpty ? "Prénom" : _firstNameController.text} ${_lastNameController.text.isEmpty ? "Nom" : _lastNameController.text}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      painter: _SemiCircleProgressPainter(
                        value: _calculateProfileCompletion() / 100,
                        progressColor: const Color(0xFF4CAF50),
                        backgroundColor: const Color(0xFFE8F5E9),
                        strokeWidth: 6,
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'complété',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_calculateProfileCompletion()}%',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildEmployeeBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('job_offers')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final offers = snapshot.data?.docs ?? [];

        final query = _searchQuery.toLowerCase().trim();
        final filteredOffers = query.isEmpty
            ? offers
            : offers.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final title = (data['title'] ?? '').toString().toLowerCase();
                final description = (data['description'] ?? '').toString().toLowerCase();
                final company = (data['company'] ?? '').toString().toLowerCase();
                return title.contains(query) ||
                    description.contains(query) ||
                    company.contains(query);
              }).toList();

        if (filteredOffers.isEmpty) {
          return Center(
            child: Text(
              query.isEmpty
                  ? 'Aucune offre disponible'
                  : 'Aucun résultat pour "$_searchQuery"',
            ),
          );
        }

        _queueAutoApplications(filteredOffers);

         if (!mounted) return const SizedBox.shrink();

        return ListView.builder(
           padding: const EdgeInsets.symmetric(vertical: 8),
           itemCount: filteredOffers.length,
           itemBuilder: (context, index) =>
               _buildJobOfferCard(filteredOffers[index]),
           physics: const AlwaysScrollableScrollPhysics(),
         );
      },
    );
  }

  String _extractOfferEmail(Map<String, dynamic> data) {
    final emailPattern = RegExp(
      r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
      caseSensitive: false,
    );
    final values = [
      data['contactEmail'],
      data['description'],
      data['title'],
      data['company'],
      data['source'],
      data['url'],
    ];
    for (final value in values) {
      final match = emailPattern.firstMatch((value ?? '').toString());
      if (match != null) {
        return match.group(0) ?? '';
      }
    }
    return '';
  }

  bool _hasQueuedAutoApps = false;

  void _queueAutoApplications(List<QueryDocumentSnapshot> offers) {
    if (!_autoApplyEnabled || _isLoading || offers.isEmpty) return;
    if (!_hasQueuedAutoApps) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _autoApplyEnabled) {
          _processAutoApplications(offers);
          _hasQueuedAutoApps = true;
        }
      });
    }
  }

  void _processAutoApplications(List<QueryDocumentSnapshot> offers) {
    for (final doc in offers) {
      if (_appliedOfferIds.contains(doc.id) ||
          _pendingAutoApplyOfferIds.contains(doc.id)) {
        continue;
      }
      _pendingAutoApplyOfferIds.add(doc.id);
      Future.microtask(() {
        if (mounted && _autoApplyEnabled && !_appliedOfferIds.contains(doc.id)) {
          _applyToOffer(doc, true);
        }
      });
    }
  }

  Widget _buildNotificationButton() {
    if (userSession.userId == null) {
      return const SizedBox.shrink();
    }

    final unreadStream = firestore
        .collection('jobseeker_notifications')
        .where('userId', isEqualTo: userSession.userId)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: unreadStream,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs
                .where((doc) => (doc.data() as Map<String, dynamic>)['read'] == false)
                .length ??
            0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: _openNotificationsSheet,
              icon: const Icon(Icons.notifications_outlined),
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
    _markNotificationsAsRead();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final notificationsStream = firestore
            .collection('jobseeker_notifications')
            .where('userId', isEqualTo: userSession.userId)
            .snapshots();

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
                    stream: notificationsStream,
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
                          final data = visibleNotifications[index].data()
                              as Map<String, dynamic>;
                          return ListTile(
                            leading: Icon(
                              data['automatic'] == true
                                  ? Icons.flash_on
                                  : Icons.send_outlined,
                              color: const Color(0xFF4CAF50),
                            ),
                            title: Text(data['title'] ?? 'Candidature envoyee'),
                            subtitle: Text(data['body'] ?? ''),
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

  PreferredSizeWidget _buildEmployeeAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF4CAF50),
      foregroundColor: Colors.white,
      titleSpacing: 16,
      title: SizedBox(
        width: double.infinity,
        child: TextField(
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Rechercher par titre, description, entreprise...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
            prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.9), size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                    icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.9), size: 20),
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withOpacity(0.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white, width: 1),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          ),
        ),
      ),
      actions: [
        _buildNotificationButton(),
        IconButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Déconnexion'),
                content: const Text('Voulez-vous vraiment vous déconnecter ?'),
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
        Switch(
          value: _autoApplyEnabled,
          onChanged: (value) {
            setState(() {
              _autoApplyEnabled = value;
            });
            firestore
                .collection('jobseekers')
                .doc(userSession.userId ?? '')
                .set({'autoApply': value}, SetOptions(merge: true));
          },
          activeColor: Colors.white,
          activeTrackColor: Colors.white.withOpacity(0.3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 0 ? _buildEmployeeAppBar() : null,
      body: _currentIndex == 0 ? _buildEmployeeBody() : _buildProfileView(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() {
          _currentIndex = index;
          if (index != 1) _profilePageIndex = 0;
        }),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.work), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
        ],
      ),
    );
  }

  Widget _buildProfileView() {
    return Column(
      children: [
        _buildProfileHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildProfileMenuItem(
                icon: Icons.person,
                label: 'Informations personnelles',
                onTap: () => _openProfileSheet(
                  title: 'Informations personnelles',
                  child: _buildPersonalTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: Icons.family_restroom,
                label: 'Situation familiale',
                onTap: () => _openProfileSheet(
                  title: 'Situation familiale',
                  child: _buildFamilyTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: Icons.school,
                label: 'Formations & Diplômes',
                onTap: () => _openProfileSheet(
                  title: 'Formations & Diplômes',
                  child: _buildEducationTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: Icons.work,
                label: 'Expérience professionnelle',
                onTap: () => _openProfileSheet(
                  title: 'Expérience professionnelle',
                  child: _buildExperienceTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: Icons.language,
                label: 'Langues & Loisirs',
                onTap: () => _openProfileSheet(
                  title: 'Langues & Loisirs',
                  child: _buildLanguagesTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: Icons.tune,
                label: 'Préférences',
                onTap: () => _openProfileSheet(
                  title: 'Préférences',
                  child: _buildPreferencesTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: Icons.info,
                label: 'À propos de moi',
                onTap: () => _openProfileSheet(
                  title: 'À propos de moi',
                  child: _buildAboutTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: Icons.picture_as_pdf,
                label: 'Générer mon CV',
                onTap: _generateCV,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF4CAF50)),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _openProfileSheet({required String title, required Widget child}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildJobOfferCard(QueryDocumentSnapshot offer) {
    final data = offer.data() as Map<String, dynamic>?;
    final logoUrl = data?['logoUrl'] as String?;
    final title = data?['title'] ?? '';
    final contract = data?['contract'] as String?;
    final city = data?['city'] ?? '';
    final description = (data?['description'] ?? '') as String;
    final createdAt = data?['createdAt'];
    int daysAgo = 0;
    if (createdAt != null) {
      final date = (createdAt as Timestamp).toDate();
      daysAgo = DateTime.now().difference(date).inDays;
    }
    final descriptionPreview =
        description.split(RegExp(r'\s+')).take(100).join(' ') +
        (description.split(RegExp(r'\s+')).length > 100 ? '...' : '');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                logoUrl != null && logoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: logoUrl,
                        width: 50,
                        height: 50,
                        placeholder: (context, url) =>
                            const CircularProgressIndicator(),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.work, size: 40),
                      )
                    : const Icon(Icons.work, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (contract != null && contract.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          contract,
                          style: const TextStyle(color: Colors.blueGrey),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (city.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(city, style: const TextStyle(color: Colors.black54)),
            ],
            if (descriptionPreview.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                descriptionPreview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  daysAgo == 0
                      ? 'Publié aujourd\'hui'
                      : 'Publié il y a $daysAgo jour${daysAgo > 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                TextButton(
                  onPressed: () {
                    if (data != null) {
                      setState(() => _selectedOffer = {
                        'id': offer.id,
                        ...Map<String, dynamic>.from(data!),
                      });
                    }
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.9,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  data?['title'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (data?['source'] != null) ...[
                                      Text(
                                        'Source: ${data?['source']}',
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    Text(
                                      'Entreprise: ${data?['company'] ?? ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Localisation: ${data?['city'] ?? ''}, ${data?['country'] ?? ''}',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Salaire: ${data?['salary'] ?? ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Type: ${data?['contract'] ?? ''}'),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Description:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(description),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: FilledButton.icon(
                                  onPressed: _appliedOfferIds.contains(offer.id)
                                      ? null
                                      : () {
                                          Navigator.pop(context);
                                          if (data != null) {
                                            setState(() => _selectedOffer = {
                                              'id': offer.id,
                                              ...Map<String, dynamic>.from(data),
                                            });
                                          }
                                          _applyToOffer();
                                        },
                                  icon: const Icon(Icons.send),
                                  label: Text(
                                    _appliedOfferIds.contains(offer.id)
                                        ? 'Deja postule'
                                        : 'Postuler maintenant',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Voir l\'offre',
                    style: TextStyle(color: Color(0xFF4CAF50)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _personalFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            TextFormField(
              controller: _firstNameController,
              decoration: InputDecoration(
                labelText: 'Prénom',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameController,
              decoration: InputDecoration(
                labelText: 'Nom',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.email,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: 'Numéro de téléphone',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.phone,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _countryController,
              decoration: InputDecoration(
                labelText: 'Pays',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.public,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cityController,
              decoration: InputDecoration(
                labelText: 'Ville',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.location_city,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _saveProfile('personal'),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _familyFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              value: _selectedMaritalStatus,
              decoration: InputDecoration(
                labelText: 'Situation matrimoniale',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.favorite,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              items: _maritalStatusOptions
                  .map(
                    (status) =>
                        DropdownMenuItem(value: status, child: Text(status)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedMaritalStatus = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _childrenCountController,
              decoration: InputDecoration(
                labelText: "Nombre d'enfants",
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.child_friendly,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _saveProfile('family'),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEducationTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _pickDiploma,
            icon: const Icon(Icons.upload_file),
            label: const Text('Uploader un diplôme'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Diplômes uploadés',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_diplomas.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.school),
                title: Text('Aucun diplôme uploadé'),
              ),
            )
          else
            ...List.generate(
              _diplomas.length,
              (index) => Card(
                child: ListTile(
                  leading: _diplomas[index].toLowerCase().contains('.pdf')
                      ? const Icon(
                          Icons.picture_as_pdf,
                          color: Color(0xFF4CAF50),
                          size: 40,
                        )
                      : SizedBox(
                          width: 40,
                          height: 40,
                          child: CachedNetworkImage(
                            imageUrl: _diplomas[index],
                            placeholder: (context, url) =>
                                const CircularProgressIndicator(),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.error),
                            fit: BoxFit.cover,
                          ),
                        ),
                  title: Text(
                    'Diplôme ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    _diplomas[index].toLowerCase().contains('.pdf')
                        ? 'PDF'
                        : 'Image',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, color: Colors.blue),
                        onPressed: () async {
                          final url = _diplomas[index];
                          final uri = Uri.parse(url);
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erreur: ${e.toString()}'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            setState(() => _diplomas.removeAt(index)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : () => _saveProfile('education'),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _experienceFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            TextFormField(
              controller: _currentSalaryController,
              decoration: InputDecoration(
                labelText: 'Salaire actuel',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.attach_money,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _experienceMonthsController,
              decoration: InputDecoration(
                labelText: 'Expérience (mois)',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.access_time,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _experienceYearsController,
              decoration: InputDecoration(
                labelText: 'Expérience (années)',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.access_time,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Travail actuellement'),
              value: _isCurrentlyWorking,
              onChanged: (value) => setState(() => _isCurrentlyWorking = value),
            ),
            if (_isCurrentlyWorking) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _currentPositionController,
                decoration: InputDecoration(
                  labelText: 'Poste occupé',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.work,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedContractType,
                decoration: InputDecoration(
                  labelText: 'Type de contrat',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.work_outline,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                items: _contractTypes
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedContractType = value),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _saveProfile('experience'),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguagesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          const Text(
            'Langues parlées',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _languageController,
                  decoration: InputDecoration(
                    labelText: 'Ajouter une langue',
                    prefixIcon: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.language,
                        size: 18,
                        color: Color(0xFF4CAF50),
                      ),
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
                      borderSide: const BorderSide(
                        color: Color(0xFF4CAF50),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: _addLanguage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_languages.isEmpty)
            const Text('Aucune langue ajoutée')
          else
            ...List.generate(
              _languages.length,
              (index) => ListTile(
                title: Text(_languages[index]['name']),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeLanguage(index),
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text('Loisirs', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _hobbyController,
                  decoration: InputDecoration(
                    labelText: 'Ajouter un loisir',
                    prefixIcon: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.sports_soccer,
                        size: 18,
                        color: Color(0xFF4CAF50),
                      ),
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
                      borderSide: const BorderSide(
                        color: Color(0xFF4CAF50),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: _addHobby,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_hobbies.isEmpty)
            const Text('Aucun loisir ajouté')
          else
            ...List.generate(
              _hobbies.length,
              (index) => ListTile(
                title: Text(_hobbies[index]['name']),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeHobby(index),
                ),
              ),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : () => _saveProfile('languages'),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _preferencesFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            TextFormField(
              controller: _availabilityController,
              decoration: InputDecoration(
                labelText: 'Disponibilité',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desiredSalaryController,
              decoration: InputDecoration(
                labelText: 'Salaire souhaité',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.attach_money,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedWorkMode,
              decoration: InputDecoration(
                labelText: 'Mode de travail',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.work,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              items: _workModes
                  .map(
                    (mode) => DropdownMenuItem(value: mode, child: Text(mode)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedWorkMode = value),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _saveProfile('preferences'),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _aboutFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            TextFormField(
              controller: _aboutController,
              decoration: InputDecoration(
                labelText: 'À propos de moi',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.info,
                    size: 18,
                    color: Color(0xFF4CAF50),
                  ),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _generateAboutWithGemini,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Générer avec l\'IA'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _saveProfile('about'),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _generateAboutWithGemini() async {
    setState(() => _isLoading = true);
    try {
      final languages = _languages.map((l) => l['name']).join(', ');
      final prompt =
          'Génère un texte "À propos de moi" pour un profil professionnel avec les informations suivantes: '
          'Prénom: ${_firstNameController.text}, Nom: ${_lastNameController.text}, '
          'Ville: ${_cityController.text}, Pays: ${_countryController.text}, '
          'Expérience: ${_experienceYearsController.text} ans, ${_experienceMonthsController.text} mois, '
          'Poste actuel: ${_currentPositionController.text}, '
          'Langues: $languages. '
          'Rédige un texte professionnel et engageant de 3-4 phrases maximum.';

      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=AIzaSyBKm0szKUWlOf5zjzHXedkx9GeDo6gPf_M',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final generatedText =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        if (generatedText.isNotEmpty) {
          setState(() {
            _aboutController.text = generatedText.trim();
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Texte généré avec succès')),
            );
          }
        }
      } else {
        final errorMsg = response.body.isNotEmpty
            ? response.body
            : 'Model non trouvé - Vérifiez la clé API Gemini';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur API: ${response.statusCode}\n$errorMsg'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur réseau: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class CompanyDashboard extends StatefulWidget {
  const CompanyDashboard({super.key});

  @override
  State<CompanyDashboard> createState() => _CompanyDashboardState();
}

class _CompanyDashboardState extends State<CompanyDashboard> {
  bool _isLoading = false;

  void _logout() async {
    setState(() => _isLoading = true);
    await userSession.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace entreprise'),
        backgroundColor: const Color(0xFF00BCD4),
        foregroundColor: Colors.white,
        actions: [
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
              style: TextStyle(color: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _logoUrl;
  String? _editingOfferId;
  bool _showForm = false;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();
  final _siteFormKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _companyController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _salaryController = TextEditingController();
  final _skillsController = TextEditingController();
  final _contactEmailController = TextEditingController();

  final _siteNameController = TextEditingController();
  final _siteUrlController = TextEditingController();
  final _selectorNameController = TextEditingController();
  final _selectorValueController = TextEditingController();
  bool _showSelectorForm = false;
  String? _editingSiteId;
  String? _selectedSiteIdForSelector;
  String? _editingSelectorId;
  bool _showSiteForm = false;
  bool _showSelectorList = false;

  String? _contractType;
  DateTime? _expiryDate;

  final List<String> _contractTypes = [
    'CDI',
    'CDD',
    'Temps partiel',
    'Freelance',
    'Stage',
    'Intérim',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _companyController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _descriptionController.dispose();
    _salaryController.dispose();
    _skillsController.dispose();
    _contactEmailController.dispose();
    _siteNameController.dispose();
    _siteUrlController.dispose();
    _selectorNameController.dispose();
    _selectorValueController.dispose();
    super.dispose();
  }

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
        print('Cloudinary response status: ${response.statusCode}');
        print('Cloudinary response body: $respStr');

        if (response.statusCode == 200) {
          final data = jsonDecode(respStr);
          print('Cloudinary response: $data');
          if (data['secure_url'] != null) {
            setState(() => _logoUrl = data['secure_url']);
            print('Logo URL set to: $_logoUrl');
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Erreur: URL du logo non retournée par Cloudinary',
                  ),
                ),
              );
            }
          }
        } else if (response.statusCode == 401) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Erreur d\'authentification Cloudinary (401).\n\n1. Vérifiez que le cloud name "demjpkcfj" est correct\n2. Confirmez que l\'upload preset "vera2026" existe\n3. Vérifiez que "Allow unsigned uploads" est activé pour cet upload preset\n4. Essayez de créer un nouvel upload preset de test\n5. Vérifiez les restrictions de dossier ou de type de fichier',
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Erreur upload: Code ${response.statusCode}\nResponse: $respStr',
                ),
              ),
            );
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

  Future<void> _saveJobOffer() async {
    if (_editingOfferId != null) {
      await _updateJobOffer();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await firestore.collection('job_offers').add({
        'title': _titleController.text,
        'company': _companyController.text,
        'city': _cityController.text,
        'country': _countryController.text,
        'description': _descriptionController.text,
        'salary': _salaryController.text,
        'contract': _contractType,
        'skills': _skillsController.text.split(','),
        'expiryDate': _expiryDate?.toIso8601String(),
        'logoUrl': _logoUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'source': null,
        'contactEmail': _contactEmailController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Offre d\'emploi créée')));
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editOffer(DocumentSnapshot offer) {
    setState(() {
      _editingOfferId = offer.id;
      _titleController.text = offer['title'] ?? '';
      _companyController.text = offer['company'] ?? '';
      _cityController.text = offer['city'] ?? '';
      _countryController.text = offer['country'] ?? '';
      _descriptionController.text = offer['description'] ?? '';
      _salaryController.text = offer['salary'] ?? '';
      _contractType = offer['contract'] ?? '';
      _skillsController.text = (offer['skills'] as List?)?.join(',') ?? '';
      _contactEmailController.text = offer['contactEmail'] ?? '';
      _expiryDate = offer['expiryDate'] != null
          ? DateTime.tryParse(offer['expiryDate'].toString())
          : null;
      _logoUrl =
          offer['logoUrl'] != null && offer['logoUrl'].toString().isNotEmpty
          ? offer['logoUrl'].toString()
          : null;
    });
    _showForm = true;
  }

  Future<void> _updateJobOffer() async {
    if (!_formKey.currentState!.validate() || _editingOfferId == null) return;
    setState(() => _isLoading = true);
    try {
      await firestore.collection('job_offers').doc(_editingOfferId).update({
        'title': _titleController.text,
        'company': _companyController.text,
        'city': _cityController.text,
        'country': _countryController.text,
        'description': _descriptionController.text,
        'salary': _salaryController.text,
        'contract': _contractType,
        'skills': _skillsController.text.split(','),
        'expiryDate': _expiryDate?.toIso8601String(),
        'logoUrl': _logoUrl,
        'source': null,
        'contactEmail': _contactEmailController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Offre mise à jour')));
        _cancelEdit();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _cancelEdit() {
    _formKey.currentState?.reset();
    setState(() {
      _editingOfferId = null;
      _logoUrl = null;
      _contractType = null;
      _expiryDate = null;
    });
  }

  Future<void> _deleteOffer(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l\'offre'),
        content: const Text('Êtes-vous sûr de vouloir supprimer cette offre?'),
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

  void _clearForm() {
    _formKey.currentState?.reset();
    setState(() {
      _logoUrl = null;
      _contractType = null;
      _expiryDate = null;
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  void _logout() async {
    setState(() => _isLoading = true);
    await userSession.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  PreferredSizeWidget _buildAppBar() {
    String title;
    if (_showSelectorList && _selectedSiteIdForSelector != null) {
      title = 'Sélecteurs';
    } else if (_showForm) {
      title = 'Ajouter une offre';
    } else if (_currentIndex == 0) {
      title = 'Liste des offres d\'emploi';
    } else {
      title = 'Liste des offres';
    }
    return AppBar(
      title: Text(title),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4CAF50), Color(0xFF00BCD4)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
      foregroundColor: Colors.white,
      leading: (_showForm || _showSelectorList)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (_showSelectorList) {
                  _closeSelectorList();
                } else {
                  setState(() {
                    _showForm = false;
                    _editingOfferId = null;
                  });
                }
              },
            )
          : null,
      actions: !_showForm && !_showSelectorList
          ? [
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'add':
                      setState(() {
                        _showForm = true;
                        _editingOfferId = null;
                        _clearForm();
                      });
                      break;
                    case 'logout':
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
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'add',
                    child: Text('Ajouter une offre'),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Text('Déconnexion'),
                  ),
                ],
              ),
            ]
          : null,
    );
  }

  Future<void> _saveSite() async {
    if (!_siteFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final data = {
      'name': _siteNameController.text.trim(),
      'url': _siteUrlController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_editingSiteId != null) {
        await firestore.collection('sites').doc(_editingSiteId).update(data);
      } else {
        await firestore.collection('sites').add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      _siteNameController.clear();
      _siteUrlController.clear();
      setState(() {
        _showSiteForm = false;
        _editingSiteId = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSite(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le site'),
        content: const Text('Êtes-vous sûr de vouloir supprimer ce site?'),
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
      await firestore.collection('sites').doc(id).delete();
    }
  }

  void _openSelectorList(String siteId) {
    setState(() {
      _selectedSiteIdForSelector = siteId;
      _showSelectorList = true;
      _showSelectorForm = false;
      _editingSelectorId = null;
      _selectorNameController.clear();
      _selectorValueController.clear();
    });
  }

  void _closeSelectorList() {
    setState(() {
      _selectedSiteIdForSelector = null;
      _showSelectorList = false;
      _showSelectorForm = false;
      _editingSelectorId = null;
      _selectorNameController.clear();
      _selectorValueController.clear();
    });
  }

  Future<void> _saveSelector() async {
    if (_selectedSiteIdForSelector == null ||
        !_siteFormKey.currentState!.validate())
      return;
    setState(() => _isLoading = true);

    final collection = firestore
        .collection('sites')
        .doc(_selectedSiteIdForSelector)
        .collection('selectors');
    final data = {
      'name': _selectorNameController.text.trim(),
      'value': _selectorValueController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_editingSelectorId != null) {
        await collection.doc(_editingSelectorId).update(data);
      } else {
        await collection.add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      _selectorNameController.clear();
      _selectorValueController.clear();
      setState(() {
        _showSelectorForm = false;
        _editingSelectorId = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _editSelector(QueryDocumentSnapshot selector) {
    final data = selector.data() as Map<String, dynamic>?;
    setState(() {
      _editingSelectorId = selector.id;
      _selectorNameController.text = data?['name'] ?? '';
      _selectorValueController.text = data?['value'] ?? '';
      _showSelectorForm = true;
    });
  }

  Future<void> _deleteSelector(String id) async {
    if (_selectedSiteIdForSelector == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le sélecteur'),
        content: const Text('Êtes-vous sûr de vouloir supprimer ce sélecteur?'),
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
      await firestore
          .collection('sites')
          .doc(_selectedSiteIdForSelector)
          .collection('selectors')
          .doc(id)
          .delete();
    }
  }

  Widget _buildJobOffersTab() {
    if (_showForm) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isLoading) const LinearProgressIndicator(),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Titre',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.title,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                validator: (v) => v!.isEmpty ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _companyController,
                decoration: InputDecoration(
                  labelText: 'Entreprise',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.business,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactEmailController,
                decoration: InputDecoration(
                  labelText: 'Email de contact',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.email,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cityController,
                decoration: InputDecoration(
                  labelText: 'Ville',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.location_city,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _countryController,
                decoration: InputDecoration(
                  labelText: 'Pays',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.public,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.description,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _salaryController,
                decoration: InputDecoration(
                  labelText: 'Salaire',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.attach_money,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _contractType,
                decoration: InputDecoration(
                  labelText: 'Type de contrat',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.work_outline,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                items: _contractTypes
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _contractType = value),
                validator: (value) => value == null ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _skillsController,
                decoration: InputDecoration(
                  labelText: 'Compétences (séparées par virgule)',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.code,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: "Date d'expiration",
                    prefixIcon: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: Color(0xFF4CAF50),
                      ),
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
                      borderSide: const BorderSide(
                        color: Color(0xFF4CAF50),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  child: Text(
                    _expiryDate != null
                        ? '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}'
                        : 'Sélectionner une date',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _logoUrl != null && _logoUrl!.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Image.network(
                              _logoUrl!,
                              height: 80,
                              width: 80,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox(
                                      height: 80,
                                      width: 80,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 80,
                                  width: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.broken_image,
                                    size: 40,
                                  ),
                                );
                              },
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
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Ajouter l'offre"),
              ),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('job_offers')
          .orderBy('createdAt', descending: true)
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
          return const Center(child: Text('Aucune offre disponible'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: offers.length,
          itemBuilder: (context, index) {
            final offer = offers[index];
            final data = offer.data() as Map<String, dynamic>?;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.work, color: Color(0xFF4CAF50)),
                title: Text(data?['title'] ?? ''),
                subtitle: Text(
                  '${data?['company'] ?? ''} - ${data?['city'] ?? ''}',
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

  Widget _buildCompaniesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('users')
          .where('role', isEqualTo: UserRole.company.name)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final companies = snapshot.data?.docs ?? [];
        if (companies.isEmpty) {
          return const Center(child: Text('Aucune entreprise'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: companies.length,
          itemBuilder: (context, index) {
            final company = companies[index];
            final data = company.data() as Map<String, dynamic>?;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.business, color: Color(0xFF00BCD4)),
                title: Text(data?['email'] ?? 'Entreprise'),
                subtitle: Text(data?['role'] ?? ''),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSitesTab() {
    if (_showSelectorList && _selectedSiteIdForSelector != null) {
      return Column(
        children: [
          if (_showSelectorForm)
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _siteFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isLoading) const LinearProgressIndicator(),
                    TextFormField(
                      controller: _selectorNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom du sélecteur',
                        prefixIcon: Icon(Icons.label),
                      ),
                      validator: (v) => v!.isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _selectorValueController,
                      decoration: const InputDecoration(
                        labelText: 'Valeur du sélecteur',
                        prefixIcon: Icon(Icons.code),
                      ),
                      validator: (v) => v!.isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveSelector,
                      child: const Text('Enregistrer le sélecteur'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: firestore
                  .collection('sites')
                  .doc(_selectedSiteIdForSelector)
                  .collection('selectors')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final selectors = snapshot.data?.docs ?? [];
                if (selectors.isEmpty) {
                  return const Center(child: Text('Aucun sélecteur'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: selectors.length,
                  itemBuilder: (context, index) {
                    final selector = selectors[index];
                    final selectorData =
                        selector.data() as Map<String, dynamic>?;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.select_all),
                        title: Text(selectorData?['name'] ?? 'Sans nom'),
                        subtitle: Text(selectorData?['value'] ?? 'Sans valeur'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editSelector(selector),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteSelector(selector.id),
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
        ],
      );
    }
    return _showSiteForm
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _siteFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isLoading) const LinearProgressIndicator(),
                  TextFormField(
                    controller: _siteNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nom du site',
                      prefixIcon: Icon(Icons.web),
                    ),
                    validator: (v) => v!.isEmpty ? 'Requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _siteUrlController,
                    decoration: const InputDecoration(
                      labelText: 'URL du site',
                      prefixIcon: Icon(Icons.link),
                    ),
                    validator: (v) => v!.isEmpty ? 'Requis' : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveSite,
                    child: Text(
                      _editingSiteId != null ? 'Mettre à jour' : 'Ajouter',
                    ),
                  ),
                ],
              ),
            ),
          )
        : StreamBuilder<QuerySnapshot>(
            stream: firestore
                .collection('sites')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final sites = snapshot.data?.docs ?? [];
              if (sites.isEmpty) {
                return const Center(child: Text('Aucun site'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: sites.length,
                itemBuilder: (context, index) {
                  final site = sites[index];
                  final siteData = site.data() as Map<String, dynamic>?;
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.web),
                      title: Text(siteData?['name'] ?? 'Sans nom'),
                      subtitle: Text(siteData?['url'] ?? 'Sans URL'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.visibility,
                              color: Colors.blue,
                            ),
                            onPressed: () async {
                              final url = siteData?['url'] as String?;
                              if (url == null || url.isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('URL du site introuvable'),
                                    ),
                                  );
                                }
                                return;
                              }
                              final uri = Uri.parse(url);
                              try {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erreur: ${e.toString()}'),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteSite(site.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.list, color: Colors.green),
                            onPressed: () => _openSelectorList(site.id),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildJobOffersTab(),
          _buildCompaniesTab(),
          _buildSitesTab(),
        ],
      ),
      floatingActionButton:
          _currentIndex == 2 &&
              _showSelectorList &&
              _selectedSiteIdForSelector != null
          ? FloatingActionButton(
              onPressed: () => setState(() => _showSelectorForm = true),
              child: const Icon(Icons.add),
            )
          : (_currentIndex == 2
                ? FloatingActionButton(
                    onPressed: () => setState(() => _showSiteForm = true),
                    child: const Icon(Icons.add),
                  )
                : null),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() {
          _currentIndex = index;
        }),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.work), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.business), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.web), label: ''),
        ],
      ),
    );
  }
}

class _SemiCircleProgressPainter extends CustomPainter {
  final double value;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _SemiCircleProgressPainter({
    required this.value,
    this.backgroundColor = const Color(0x33FFFFFF),
    this.progressColor = Colors.white,
    this.strokeWidth = 6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    paint.color = backgroundColor;
    canvas.drawArc(rect, pi, pi, true, paint);

    final clampedValue = value.clamp(0.0, 1.0);
    paint.color = progressColor;
    canvas.drawArc(rect, pi, clampedValue * pi, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
