import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart' as phicons;
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../auth_service.dart';
import 'chat_screen.dart';
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
  final TextEditingController _careerObjectiveController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _currentIndex = 0;
  int _profilePageIndex = 0;
  int _currentHomePage = 0;
  int _unreadMessageCount = 0;
  final List<Map<String, dynamic>> _diplomas = [];
  String _searchQuery = '';
  bool _showSearchBarHome = false;
  Map<String, dynamic>? _selectedOffer;
  bool _autoApplyEnabled = false;
  bool _showMessageActions = false;
  final Set<String> _appliedOfferIds = {};
  final Set<String> _pendingAutoApplyOfferIds = {};
  final Set<String> _favoriteOfferIds = {};
  final PageController _homePageController = PageController();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Map<String, int> _compatibilityCache = {};
  late final Stream<QuerySnapshot> _homeOffersStream;
  // GCP API key must not be hardcoded. Provide via --dart-define GCP_API_KEY=your_key
  final String _gcpApiKey = const String.fromEnvironment('GCP_API_KEY');

  Stream<QuerySnapshot> get _notificationStream {
    if (userSession.userId == null || userSession.userId!.isEmpty) {
      return Stream<QuerySnapshot>.empty();
    }
    return firestore
        .collection('jobseeker_notifications')
        .where('userId', isEqualTo: userSession.userId)
        .where('read', isEqualTo: false)
        .limit(30)
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _homeOffersStream = firestore
        .collection('job_offers')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
    _setupProfileListeners();
    _loadProfileData();
    _initNotifications();
    _loadAppliedOffers();

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

  Future<void> _markNotificationAsRead(String notificationId) async {
    try {
      await firestore
          .collection('jobseeker_notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (_) {}
  }

  Future<void> _applyToOffer([QueryDocumentSnapshot? offer, bool automatic = false, BuildContext? dialogContext]) async {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur serveur - candidature non envoyée')),
          );
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
          if (dialogContext != null && Navigator.canPop(dialogContext)) {
            Navigator.pop(dialogContext);
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
          _careerObjectiveController.text = data['careerObjective'] ?? '';
          if (data['diplomas'] != null) {
            _diplomas.clear();
            _diplomas.addAll(
              List<Map<String, dynamic>>.from(
                (data['diplomas'] as List).map(
                  (e) => Map<String, dynamic>.from(e),
                ),
              ),
            );
          }
          if (data['favoriteOfferIds'] != null) {
            _favoriteOfferIds.clear();
            _favoriteOfferIds.addAll(
              List<String>.from(data['favoriteOfferIds'] as List),
            );
          }
          _profilePhotoUrl = data['profilePhotoUrl'];
          _autoApplyEnabled = data['autoApply'] ?? false;
        });
        if (_careerObjectiveController.text.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showCareerObjectiveReminder();
            }
          });
        }
      }
    } catch (e) {}
  }

  void _showCareerObjectiveReminder() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Objectif de carrière'),
        content: const Text(
          'Votre objectif de carrière n\'est pas renseigné. '
          'Complétez-le pour profiter de recommandations personnalisées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openCareerObjectiveSheet();
            },
            child: const Text('Renseigner'),
          ),
        ],
      ),
    );
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
    final controllers = [
      _firstNameController,
      _lastNameController,
      _emailController,
      _phoneController,
      _countryController,
      _cityController,
      _childrenCountController,
      _currentSalaryController,
      _experienceMonthsController,
      _experienceYearsController,
      _currentPositionController,
      _availabilityController,
      _desiredSalaryController,
      _aboutController,
      _careerObjectiveController,
    ];
    for (final controller in controllers) {
      controller.removeListener(_refreshProfileCompletion);
    }
    _aboutController.dispose();
    _careerObjectiveController.dispose();
    _homePageController.dispose();
    super.dispose();
  }

  void _logout() async {
    setState(() => _isLoading = true);
    await userSession.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  void _setupProfileListeners() {
    final controllers = [
      _firstNameController,
      _lastNameController,
      _emailController,
      _phoneController,
      _countryController,
      _cityController,
      _childrenCountController,
      _currentSalaryController,
      _experienceMonthsController,
      _experienceYearsController,
      _currentPositionController,
      _availabilityController,
      _desiredSalaryController,
      _aboutController,
      _careerObjectiveController,
    ];
    for (final controller in controllers) {
      controller.addListener(_refreshProfileCompletion);
    }
  }

  void _refreshProfileCompletion() {
    if (mounted) setState(() {});
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

  Future<void> _persistFavorites() async {
    if (userSession.userId == null) return;
    try {
      await firestore
          .collection('jobseekers')
          .doc(userSession.userId)
          .set({'favoriteOfferIds': _favoriteOfferIds.toList()}, SetOptions(merge: true));
    } catch (e) {}
  }

  Future<void> _generateCV() async {
    setState(() => _isLoading = true);
    try {
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
      final diplomas = _diplomas.map((d) {
        final name = d['name'] ?? '';
        final date = d['date'] ?? '';
        final school = d['school'] ?? '';
        final parts = [name];
        if (date.isNotEmpty) parts.add('($date)');
        if (school.isNotEmpty) parts.add('- $school');
        return parts.join(' ');
      }).join('\n');

      final pdf = pw.Document();

      pw.MemoryImage? profileImage;
      if (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty) {
        try {
          final response = await http.get(Uri.parse(_profilePhotoUrl!));
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
                  _buildPdfRow('Situation familiale', maritalStatus),
                  _buildPdfRow('Enfants', childrenCount),
                ]),
                _buildPdfSection(title: 'EXPÉRIENCE PROFESSIONNELLE', children: [
                  if (currentPosition.isNotEmpty) _buildPdfRow('Poste actuel', currentPosition),
                  _buildPdfRow('Expérience', '$experienceYears ans, $experienceMonths mois'),
                  if (currentSalary.isNotEmpty) _buildPdfRow('Salaire actuel', currentSalary),
                  _buildPdfRow('Type de contrat', contractType),
                  if (availability.isNotEmpty) _buildPdfRow('Disponibilité', availability),
                ]),
                _buildPdfSection(title: 'FORMATIONS & DIPLÔMES', children: [
                  if (diplomas.isNotEmpty)
                    pw.Text(diplomas, style: pw.TextStyle(fontSize: 11))
                  else
                    pw.Text('Aucun diplôme renseigné', style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic)),
                ]),
                _buildPdfSection(title: 'LANGUES & LOISIRS', children: [
                  if (languages.isNotEmpty) _buildPdfRow('Langues', languages),
                  if (hobbies.isNotEmpty) _buildPdfRow('Loisirs', hobbies),
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

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Mon CV'),
            content: SizedBox(
              width: double.maxFinite,
              height: 450,
              child: PdfPreview(
                build: (PdfPageFormat format) => pdf.save(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final bytes = await pdf.save();
                  Printing.sharePdf(
                    bytes: bytes,
                    filename: 'cv_${name.replaceAll(' ', '_').toLowerCase()}.pdf',
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('Partager PDF'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur génération PDF: ${e.toString()}')),
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
            width: 130,
            child: pw.Text(
              '$label :',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
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
    if (_isCurrentlyWorking) {
      total += 10;
      if (_currentPositionController.text.isNotEmpty) filled++;
      total += 10;
      if (_selectedContractType != null) filled++;
    }
    total += 10;
    if (_availabilityController.text.isNotEmpty) filled++;
    total += 10;
    if (_selectedWorkMode != null) filled++;
    total += 10;
    if (_aboutController.text.isNotEmpty) filled++;
    total += 10;
    if (_diplomas.isNotEmpty) filled++;
    return total > 0 ? ((filled / total) * 100).round() : 0;
  }

  String _getProfileSectionTitle() {
    switch (_profilePageIndex) {
      case 0:
        return 'Informations personnelles';
      case 1:
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
        'careerObjective': _careerObjectiveController.text,
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
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
            await _showDiplomaFormDialog(url: data['secure_url']);
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

  Future<void> _showDiplomaFormDialog({int? index, String? url}) async {
    final isEdit = index != null && url == null;
    final existing = isEdit ? _diplomas[index] : null;
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final dateController = TextEditingController(text: existing?['date'] ?? '');
    final schoolController = TextEditingController(text: existing?['school'] ?? '');

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Modifier le diplôme' : 'Ajouter un diplôme'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du diplôme',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Date d\'obtention',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: schoolController,
                decoration: const InputDecoration(
                  labelText: 'École / Lycée / Collège',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final date = dateController.text.trim();
              final school = schoolController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Veuillez saisir le nom du diplôme')),
                );
                return;
              }
              Navigator.pop(context, {
                'url': url ?? existing?['url'] ?? '',
                'name': name,
                'date': date,
                'school': school,
              });
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (result == null) return;
    setState(() {
      if (isEdit) {
        _diplomas[index] = result;
      } else {
        _diplomas.add(result);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diplôme enregistré avec succès')),
      );
    }
  }

  void _editDiploma(int index) {
    _showDiplomaFormDialog(index: index);
  }

  void _removeDiploma(int index) {
    setState(() => _diplomas.removeAt(index));
  }

  Widget _buildProfileHeader() {
    final completion = _calculateProfileCompletion();
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
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: completion / 100),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, animatedValue, child) {
                  return SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 150,
                          height: 150,
                          child: CircularProgressIndicator(
                            value: animatedValue,
                            strokeWidth: 8,
                            backgroundColor: const Color(0xFFE8F5E9),
                            color: const Color(0xFF4CAF50),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$completion%',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'complété',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeBody() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [_buildCollapsingAppBar('')];
      },
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore.collection('job_offers').orderBy('createdAt', descending: true).snapshots(),
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

          filteredOffers.sort((a, b) {
            final compatA = _calculateCompatibility((a.data() as Map<String, dynamic>?) ?? {});
            final compatB = _calculateCompatibility((b.data() as Map<String, dynamic>?) ?? {});
            return compatB.compareTo(compatA);
          });

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
            itemBuilder: (context, index) => _buildJobOfferCard(filteredOffers[index]),
            physics: const AlwaysScrollableScrollPhysics(),
          );
        },
      ),
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
    const batchSize = 3;
    var index = 0;
    void processBatch() {
      final end = (index + batchSize).clamp(0, offers.length);
      for (; index < end; index++) {
        final doc = offers[index];
        if (_appliedOfferIds.contains(doc.id) ||
            _pendingAutoApplyOfferIds.contains(doc.id)) {
          continue;
        }
        _pendingAutoApplyOfferIds.add(doc.id);
        _applyToOffer(doc, true);
      }
      if (index < offers.length && mounted && _autoApplyEnabled) {
        Future.delayed(const Duration(milliseconds: 600), processBatch);
      }
    }
    processBatch();
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
                          final body = (data['body'] ?? '').toString();
                          final preview = body.isEmpty
                              ? 'Voir les détails'
                              : body.split('.').first + '.';
                          final createdAt = data['createdAt'] as Timestamp?;
                          final dateText = createdAt != null
                              ? '${createdAt.toDate().day.toString().padLeft(2, '0')}/${createdAt.toDate().month.toString().padLeft(2, '0')}/${createdAt.toDate().year} ${createdAt.toDate().hour.toString().padLeft(2, '0')}:${createdAt.toDate().minute.toString().padLeft(2, '0')}'
                              : '';
                          return ListTile(
                            leading: Icon(
                              data['automatic'] == true
                                  ? Icons.flash_on
                                  : Icons.send_outlined,
                              color: const Color(0xFF4CAF50),
                            ),
                            title: Text(data['title'] ?? 'Notification'),
                            subtitle: Text(
                              '$preview${dateText.isEmpty ? "" : "\n$dateText"}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: data['read'] == false
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
                              await _openNotificationDetail(doc.id, data);
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

  Future<void> _openNotificationDetail(String notificationId, Map<String, dynamic> data) async {
    await _markNotificationAsRead(notificationId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    data['title'] ?? 'Notification',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data['body'] ?? 'Aucun détail disponible.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildEmployeeAppBar() {
    return AppBar(
      toolbarHeight: 32,
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF87CEEB), Color(0xFF2E7D32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
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
              _hasQueuedAutoApps = false;
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

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonjour';
    if (hour < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }
// appbar
  SliverAppBar _buildCollapsingAppBar(String title) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      expandedHeight: 60,
      collapsedHeight: 60,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.white),
        onPressed: () {
          _scaffoldKey.currentState?.openDrawer();
        },
      ),
      titleSpacing: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
        collapseMode: CollapseMode.parallax,
        title: _showSearchBarHome
            ? SizedBox(
                width: double.infinity,
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.2),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              )
            : title.isNotEmpty
                ? Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  )
                : const SizedBox.shrink(),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF87CEEB), Color.fromARGB(255, 146, 252, 151)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      actions: [
        _buildNotificationButton(),
        IconButton(
          icon: Icon(_showSearchBarHome ? Icons.close : Icons.search, color: Colors.white),
          onPressed: () {
            setState(() {
              _showSearchBarHome = !_showSearchBarHome;
            });
          },
        ),
      ],
    );
  }

  Widget _buildNavigationDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF87CEEB), Color(0xFF4CAF50)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundImage: _profilePhotoUrl != null
                              ? NetworkImage(_profilePhotoUrl!)
                              : const AssetImage('assets/vera.png') as ImageProvider,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_firstNameController.text.isNotEmpty ? _firstNameController.text : "Invité"}',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Menu de navigation',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                   Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       TweenAnimationBuilder<double>(
                         tween: Tween<double>(begin: 0, end: _calculateProfileCompletion() / 100),
                         duration: const Duration(milliseconds: 800),
                         curve: Curves.easeOutCubic,
                         builder: (context, animatedValue, child) {
                           return SizedBox(
                             width: 56,
                             height: 56,
                             child: Stack(
                               alignment: Alignment.center,
                               children: [
                                 SizedBox(
                                   width: 56,
                                   height: 56,
                                   child: CircularProgressIndicator(
                                     value: animatedValue,
                                     strokeWidth: 4,
                                     backgroundColor: Colors.white,
                                     color: const Color(0xFF4CAF50),
                                   ),
                                 ),
                                 Text(
                                   '${_calculateProfileCompletion()}%',
                                   style: const TextStyle(
                                     color: Colors.white,
                                     fontSize: 12,
                                     fontWeight: FontWeight.bold,
                                   ),
                                 ),
                               ],
                             ),
                           );
                         },
                       ),
                       const Text(
                         'profil',
                         style: TextStyle(color: Colors.white70, fontSize: 10),
                       ),
                     ],
                   ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.flag, color: Color(0xFF4CAF50)),
              title: const Text('Objectif de carrière'),
              subtitle: Text(
                _careerObjectiveController.text.isNotEmpty
                    ? _careerObjectiveController.text
                    : 'Renseignez votre objectif de carrière',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(context);
                _openCareerObjectiveSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark, color: Color(0xFF4CAF50)),
              title: const Text('Favoris'),
              subtitle: const Text('Voir vos offres favorites'),
              onTap: () {
                Navigator.pop(context);
                _openFavoritesScreen();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.autorenew,
                color: _autoApplyEnabled ? Colors.green : Colors.grey,
              ),
              title: Text(
                'Postulation automatique',
                style: TextStyle(
                  color: _autoApplyEnabled ? Colors.green : null,
                  fontWeight: _autoApplyEnabled ? FontWeight.w600 : null,
                ),
              ),
              subtitle: Text(
                _autoApplyEnabled
                    ? 'Activée - candidature auto aux offres compatibles'
                    : 'Désactivée - activez pour postuler automatiquement',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(context);
                _showAutoApplyExplanationsSheet();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFF4CAF50)),
              title: const Text('Déconnexion'),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openCareerObjectiveSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {     
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.35,
            maxChildSize: 0.85,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          height: 4,
                          width: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const Text(
                          'Objectif de carrière',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _careerObjectiveController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Ex: Travailler comme développeur Flutter',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _saveProfile('careerObjective');
                          },
                          child: const Text('Enregistrer l\'objectif'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showAutoApplyExplanationsSheet() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.autorenew, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Postulation automatique',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              final localAutoApply = ValueNotifier<bool>(_autoApplyEnabled);
              return ValueListenableBuilder<bool>(
                valueListenable: localAutoApply,
                builder: (context, value, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value
                            ? 'La postulation automatique est activée. '
                                'Votre profil sera envoyé automatiquement '
                                'aux offres compatibles avec vos compétences '
                                'et vos préférences.'
                            : 'Activez la postulation automatique pour '
                                'envoyer votre candidature automatiquement '
                                'aux offres correspondant à votre profil.',
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Activer', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Candidature automatique aux offres compatibles', style: TextStyle(fontSize: 12)),
                        value: value,
                        onChanged: (newValue) async {
                          localAutoApply.value = newValue;
                          setState(() => _autoApplyEnabled = newValue);
                          _hasQueuedAutoApps = false;
                          try {
                            await firestore
                                .collection('jobseekers')
                                .doc(userSession.userId ?? '')
                                .set({'autoApply': newValue}, SetOptions(merge: true));
                          } catch (_) {}
                        },
                        activeColor: Colors.white,
                        activeTrackColor: const Color(0xFF4CAF50),
                      ),
                      const SizedBox(height: 8),
                      const Text('Comment ça marche ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                            child: const Center(child: Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Sélection : analyse des nouvelles offres', style: TextStyle(fontSize: 13))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                            child: const Center(child: Text('2', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Compatibilité : comparaison du profil', style: TextStyle(fontSize: 13),),),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                            child: const Center(child: Text('3', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Postulation : envoi automatique du CV', style: TextStyle(fontSize: 13))),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, {String? status, double? labelFontSize, bool labelSingleLine = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        if (labelSingleLine)
          FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(color: Colors.white, fontSize: labelFontSize ?? 10),
              textAlign: TextAlign.center,
            ),
          )
        else
          Text(label, style: TextStyle(color: Colors.white, fontSize: labelFontSize ?? 10), textAlign: TextAlign.center),
        if (status != null) ...[
          const SizedBox(height: 2),
          Text(status, style: const TextStyle(color: Colors.white70, fontSize: 9), textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _buildAISuggestionCard(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return SizedBox(
      width: 180,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Icon(icon, color: const Color(0xFF4CAF50), size: 28),
                  ),
                ),
                const SizedBox(height: 10),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAISuggestionsSection() {
    final suggestions = [
      {
        'icon': phicons.PhosphorIconsRegular.paperPlaneRight,
        'title': 'Postulé à',
        'subtitle': '5 nouvelles offres',
      },
      {
        'icon': phicons.PhosphorIconsRegular.sparkle,
        'title': 'Améliorer vos compétences',
        'subtitle': 'Suivez une formation',
      },
      {
        'icon': phicons.PhosphorIconsRegular.copy,
        'title': 'Mettre à jour votre CV',
        'subtitle': 'Rafraîchissez vos expériences',
      },
      {
        'icon': phicons.PhosphorIconsRegular.userFocus,
        'title': 'Préparer vos entretiens',
        'subtitle': 'Simulez vos réponses',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'suggestions IA pour vous',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {},
              child: const Text(
                'voir tout',
                style: TextStyle(color: Color(0xFF4CAF50), fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: suggestions.map((item) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildAISuggestionCard(
                  item['icon'] as IconData,
                  item['title'] as String,
                  item['subtitle'] as String,
                  () {},
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeView() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [_buildCollapsingAppBar('')];
      },
      body: StreamBuilder<QuerySnapshot>(
        stream: _homeOffersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final offers = snapshot.data?.docs ?? [];

        final query = _searchQuery.toLowerCase().trim();
        final filteredOffers = offers
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return MapEntry(
                doc,
                _calculateCompatibility({
                  'id': doc.id,
                  ...data,
                }),
              );
            })
            .where((entry) => entry.value >= 75)
            .where((entry) {
              if (query.isEmpty) return true;
              final data = entry.key.data() as Map<String, dynamic>;
              final title = (data['title'] ?? '').toString().toLowerCase();
              final description = (data['description'] ?? '').toString().toLowerCase();
              final company = (data['company'] ?? '').toString().toLowerCase();
              return title.contains(query) ||
                  description.contains(query) ||
                  company.contains(query);
            })
            .toList();

        filteredOffers.sort((a, b) => b.value.compareTo(a.value));

        final visibleOffers = filteredOffers.take(10).toList();
        if (_currentHomePage >= visibleOffers.length && visibleOffers.isNotEmpty) {
          _currentHomePage = 0;
          _homePageController.jumpToPage(0);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Card(
                  color: const Color(0xFFE8F5E9),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage: _profilePhotoUrl != null
                            ? NetworkImage(_profilePhotoUrl!)
                            : const AssetImage('assets/vera.png') as ImageProvider,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min, 
                          children: [
                            Text(
                              '${_getGreeting()}, ${_firstNameController.text.isNotEmpty ? _firstNameController.text : 'Invité'}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            const Text(
                              'Prêt à faire décoller votre carrière aujourd\'hui',
                              style: TextStyle(fontSize: 10, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Profil complété',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_calculateProfileCompletion()}%',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: CustomPaint(
                              painter: _SemiCircleProgressPainter(
                                value: _calculateProfileCompletion() / 100,
                                progressColor: const Color(0xFF4CAF50),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ),
                const SizedBox(height: 16),
                Container(
                   height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF87CEEB), Color(0xFF4CAF50)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight, 
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: _buildStatItem(phicons.PhosphorIconsRegular.briefcase, 'Candidatures', '12', status: '2 en attente')),
                      Container(width: 1, color: Colors.white.withOpacity(0.3), height: 50),
                      Expanded(child: _buildStatItem(phicons.PhosphorIconsRegular.users, 'Entretiens', '3', status: '1 confirmé')),
                      Container(width: 1, color: Colors.white.withOpacity(0.3), height: 50),
                       Expanded(child: _buildStatItem(phicons.PhosphorIconsRegular.bookmark, 'Offres sauvegardées', '5', status: '5 disponibles', labelFontSize: 8, labelSingleLine: true)),
                      Container(width: 1, color: Colors.white.withOpacity(0.3), height: 50),
                      Expanded(child: _buildStatItem(phicons.PhosphorIconsRegular.graduationCap, 'Formations', '2', status: '1 en cours')),
                    ],
                  ),
),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     const Expanded(
                       child: Text(
                         'Offres recommandées pour vous',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                       ),
                     ),
                    TextButton(
                      onPressed: () {
                        setState(() => _currentIndex = 1);
                      },
                      child: const Text(
                        'Voir tout',
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (filteredOffers.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(phicons.PhosphorIconsRegular.info),
                    title: Text('Aucune offre disponible'),
                  ),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      height: 150,
                      child: PageView.builder(
                        controller: _homePageController,
                        itemCount: visibleOffers.length,
                        onPageChanged: (index) {
                          if (mounted) {
                            setState(() => _currentHomePage = index);
                          }
                        },
                        itemBuilder: (context, index) {
                          final offer = visibleOffers[index].key;
                          return Center(
                            child: _buildJobOfferCard(offer),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        visibleOffers.length,
                        (index) => Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: _currentHomePage == index
                                ? const Color(0xFF4CAF50)
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              Card(
                color: const Color(0xFFE8F5E9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Votre progression',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _currentIndex = 4);
                            },
                            child: const Text(
                              'Voir mon plan',
                              style: TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      height: 56,
                                      child: CircularProgressIndicator(
                                        value: _calculateProfileCompletion() / 100,
                                        strokeWidth: 4,
                                        backgroundColor: Colors.white,
                                        color: const Color(0xFF4CAF50),
                                      ),
                                    ),
                                    Text(
                                      '${_calculateProfileCompletion()}%',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Objectif : ${_careerObjectiveController.text.isNotEmpty ? _careerObjectiveController.text : 'Devenir développeur Flutter'}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: _calculateProfileCompletion() / 100,
                                  backgroundColor: Colors.white,
                                  color: const Color(0xFF4CAF50),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Vous êtes sur la bonne voie !',
                                  style: const TextStyle(color: Colors.black54, fontSize: 9),
                                  maxLines: null,
                                  overflow: TextOverflow.visible,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${100 - _calculateProfileCompletion()} étapes restantes pour atteindre votre objectif',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Icon(Icons.rocket_launch, size: 32, color: const Color(0xFF4CAF50)),
                                    Positioned(
                                      top: -8,
                                      left: -8,
                                      child: Icon(Icons.star, size: 14, color: Colors.amber),
                                    ),
                                    Positioned(
                                      top: -8,
                                      right: -8,
                                      child: Icon(Icons.star, size: 14, color: Colors.amber),
                                    ),
                                    Positioned(
                                      bottom: -8,
                                      left: -8,
                                      child: Icon(Icons.star, size: 14, color: Colors.amber),
                                    ),
                                    Positioned(
                                      bottom: -8,
                                      right: -8,
                                      child: Icon(Icons.star, size: 14, color: Colors.amber),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildAISuggestionsSection(),
            ],
          ),
        );
      },
    ),
  );
}

  Widget _buildBottomNavItem({required IconData icon, required String label, required int index}) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF4CAF50) : Colors.grey, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF4CAF50) : Colors.grey,
                  fontSize: index == 2 ? 10 : 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesView() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [_buildCollapsingAppBar('')];
      },
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
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
                      Icon(phicons.PhosphorIconsRegular.chats, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Aucun message', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(top: 8, bottom: 80),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
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
                          title: const Text('Utilisateur', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                          backgroundColor: const Color(0xFF4CAF50),
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
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_showMessageActions)
                  Column(
                    children: [
                      _buildSpeedDialItem(
                        icon: phicons.PhosphorIconsRegular.chat,
                        label: 'IA_VERA',
                        onTap: () {
                          setState(() => _showMessageActions = false);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                conversationId: null,
                                otherUserId: null,
                                otherUserName: 'IA_VERA',
                                isIaMode: true,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildSpeedDialItem(
                        icon: phicons.PhosphorIconsRegular.users,
                        label: 'Nouveau groupe',
                        onTap: () {
                          setState(() => _showMessageActions = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Fonctionnalité de groupe à venir')),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildSpeedDialItem(
                        icon: phicons.PhosphorIconsRegular.chatCircleDots,
                        label: 'Messages envoyés',
                        onTap: () {
                          setState(() => _showMessageActions = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Fonctionnalité à venir')),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                FloatingActionButton(
                  onPressed: () {
                    setState(() => _showMessageActions = !_showMessageActions);
                  },
                  backgroundColor: const Color(0xFF4CAF50),
                  child: Icon(
                    _showMessageActions ? phicons.PhosphorIconsRegular.x : phicons.PhosphorIconsRegular.chatDots,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedDialItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildNavigationDrawer(),
      appBar: null,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeView(),
          _buildEmployeeBody(),
          _buildApplicationsView(),
          _buildMessagesView(),
          _buildProfileView(),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildBottomNavItem(
              icon: phicons.PhosphorIconsRegular.house,
              label: 'Accueil',
              index: 0,
            ),
            _buildBottomNavItem(
              icon: phicons.PhosphorIconsRegular.briefcase,
              label: 'Offres',
              index: 1,
            ),
            _buildBottomNavItem(
              icon: phicons.PhosphorIconsRegular.paperPlane,
              label: 'Candidatures',
              index: 2,
            ),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _currentIndex = 3),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(phicons.PhosphorIconsRegular.chats, color: _currentIndex == 3 ? const Color(0xFF4CAF50) : Colors.grey, size: 24),
                          if (_unreadMessageCount > 0)
                            Positioned(
                              right: -6,
                              top: -6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(10),
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
                      const SizedBox(height: 4),
                      Text(
                        'Message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _currentIndex == 3 ? const Color(0xFF4CAF50) : Colors.grey,
                          fontSize: 12,
                          fontWeight: _currentIndex == 3 ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildBottomNavItem(
              icon: phicons.PhosphorIconsRegular.user,
              label: 'Profil',
              index: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileView() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [_buildCollapsingAppBar('')];
      },
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildProfileHeader(),
              const SizedBox(height: 12),
              _buildProfileMenuItem(
                icon: CupertinoIcons.person,
                label: 'Informations personnelles',
                onTap: () => _openProfileSheet(
                  title: 'Informations personnelles',
                  child: _buildPersonalTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: CupertinoIcons.heart,
                label: 'Situation familiale',
                onTap: () => _openProfileSheet(
                  title: 'Situation familiale',
                  child: _buildFamilyTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: CupertinoIcons.book,
                label: 'Formations & Diplômes',
                onTap: () => _openProfileSheet(
                  title: 'Formations & Diplômes',
                  child: _buildEducationTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: CupertinoIcons.briefcase,
                label: 'Expérience professionnelle',
                onTap: () => _openProfileSheet(
                  title: 'Expérience professionnelle',
                  child: _buildExperienceTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: CupertinoIcons.globe,
                label: 'Langues & Loisirs',
                onTap: () => _openProfileSheet(
                  title: 'Langues & Loisirs',
                  child: _buildLanguagesTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: CupertinoIcons.gear,
                label: 'Préférences',
                onTap: () => _openProfileSheet(
                  title: 'Préférences',
                  child: _buildPreferencesTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: CupertinoIcons.info_circle,
                label: 'À propos de moi',
                onTap: () => _openProfileSheet(
                  title: 'À propos de moi',
                  child: _buildAboutTab(),
                ),
              ),
              _buildProfileMenuItem(
                icon: CupertinoIcons.doc_text,
                label: 'Générer mon CV',
                onTap: _generateCV,
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.7),
              child: const Center(
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Génération du CV...',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
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

  void _openFavoritesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            toolbarHeight: 32,
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF87CEEB), Color.fromARGB(255, 96, 240, 103)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            title: const Text('Favoris'),
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: firestore.collection('job_offers').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur : ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final offers = snapshot.data?.docs ?? [];
              final favoriteOffers = offers.where((doc) => _favoriteOfferIds.contains(doc.id)).toList();

              if (favoriteOffers.isEmpty) {
                return const Center(
                  child: Text(
                    'Aucune offre favorite pour le moment.',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: favoriteOffers.length,
                itemBuilder: (context, index) => _buildJobOfferCard(favoriteOffers[index]),
              );
            },
          ),
        ),
      ),
    );
  }

  int _calculateCompatibility(Map<String, dynamic> offer) {
    final offerId = offer['id']?.toString() ?? '';
    if (offerId.isNotEmpty && _compatibilityCache.containsKey(offerId)) {
      return _compatibilityCache[offerId]!;
    }

    final title = (offer['title'] ?? '').toString();
    final company = (offer['company'] ?? '').toString();
    final description = (offer['description'] ?? '').toString();
    final skills = ((offer['skills'] as List?)?.join(' ') ?? '').toString();
    final input = '$title|$company|$description|$skills';

    var hash = 0;
    for (final unit in input.runes) {
      hash = ((hash << 5) - hash + unit) & 0x7fffffff;
    }

    final score = 75 + (hash % 26);
    if (offerId.isNotEmpty) {
      _compatibilityCache[offerId] = score;
    }
    return score;
  }

  Widget _buildDefaultCompanyLogo(String company, {double size = 36}) {
    final initial = company.isNotEmpty ? company[0].toUpperCase() : '?';
    final colors = [
      Color(0xFF4CAF50),
      Color(0xFF2196F3),
      Color(0xFFFF9800),
      Color(0xFF9C27B0),
      Color(0xFFF44336),
      Color(0xFF00BCD4),
    ];
    final color = colors[company.hashCode.abs() % colors.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.15),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.45,
          ),
        ),
      ),
    );
  }

  Widget _buildJobOfferCard(QueryDocumentSnapshot offer) {
    final data = offer.data() as Map<String, dynamic>?;
    final logoUrl = data?['logoUrl'] as String?;
    final title = data?['title'] ?? '';
    final company = data?['company'] ?? '';
    final contract = data?['contract'] as String?;
    final city = data?['city'] ?? '';
    final salary = data?['salary'] ?? '';
    final description = (data?['description'] ?? '') as String;
    final createdAt = data?['createdAt'];
    final skills = (data?['skills'] as List?)?.cast<String>() ?? [];

    bool isNew = false;
    if (createdAt != null) {
      final date = (createdAt as Timestamp).toDate();
      isNew = DateTime.now().difference(date).inDays < 7;
    }

    final compatibility = _calculateCompatibility({
      'id': offer.id,
      ...?data,
    });
    final isFavorite = _favoriteOfferIds.contains(offer.id);

    final skillsDisplay = skills.length > 3
        ? '${skills[0]}, ${skills[1]}, ${skills[2]}...'
        : skills.take(3).join(', ');

    String companyInfo = company;
    if (contract != null && contract.isNotEmpty) {
      companyInfo += ' • $contract';
    } else if (city.isNotEmpty) {
      companyInfo += ' • $city';
    }

    String? workMode;
    if (contract != null && contract.isNotEmpty) {
      workMode = contract == 'Temps partiel' ? 'Temps partiel' : 'Temps plein';
    }

    if (data == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: InkWell(
        onTap: () {
          if (data != null) {
            setState(() => _selectedOffer = {
                  'id': offer.id,
                  ...Map<String, dynamic>.from(data),
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
                        data['title'] ?? '',
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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (data['source'] != null) ...[
                            Text(
                              'Source: ${data['source']}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            'Entreprise: ${data['company'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Localisation: ${data['city'] ?? ''}, ${data['country'] ?? ''}',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Salaire: ${data['salary'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Type: ${data['contract'] ?? ''}'),
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
                                _applyToOffer(offer, false, context);
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  logoUrl != null && logoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: logoUrl,
                          width: 40,
                          height: 40,
                          placeholder: (context, url) =>
                              const CircularProgressIndicator(),
                          errorWidget: (context, url, error) =>
                              _buildDefaultCompanyLogo(company, size: 36),
                        )
                      : _buildDefaultCompanyLogo(company, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Nouveau',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          companyInfo,
                          style: const TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                        if (skillsDisplay.isNotEmpty)
                          Text(
                            skillsDisplay,
                            style: const TextStyle(color: Colors.grey, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                value: compatibility / 100,
                                strokeWidth: 3,
                                backgroundColor: Colors.grey[300],
                                color: const Color(0xFF4CAF50),
                              ),
                            ),
                            Text(
                              '$compatibility%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Compatibilité',
                          style: TextStyle(fontSize: 9, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (salary.isNotEmpty)
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              '$salary / mois',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (salary.isNotEmpty && workMode != null)
                          const SizedBox(width: 6),
                        if (workMode != null)
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              workMode,
                              style: const TextStyle(color: Colors.grey, fontSize: 9),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isFavorite) {
                              _favoriteOfferIds.remove(offer.id);
                            } else {
                              _favoriteOfferIds.add(offer.id);
                            }
                          });
                          _persistFavorites();
                        },
                        child: Icon(
                          isFavorite ? Icons.bookmark : Icons.bookmark_border,
                          color: const Color(0xFF4CAF50),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
              (index) {
                final diploma = _diplomas[index];
                final url = diploma['url'] ?? '';
                final name = diploma['name'] ?? 'Diplôme ${index + 1}';
                final date = diploma['date'] ?? '';
                final school = diploma['school'] ?? '';
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            url.toLowerCase().contains('.pdf')
                                ? const Icon(
                                    Icons.picture_as_pdf,
                                    color: Color(0xFF4CAF50),
                                    size: 40,
                                  )
                                : SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CachedNetworkImage(
                                      imageUrl: url,
                                      placeholder: (context, url) =>
                                          const CircularProgressIndicator(),
                                      errorWidget: (context, url, error) =>
                                          const Icon(Icons.error),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (date.isNotEmpty)
                                    Text(
                                      'Obtenu en $date',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (school.isNotEmpty)
                                    Text(
                                      school,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () async {
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
                              icon: const Icon(Icons.visibility, size: 18),
                              label: const Text('Voir'),
                            ),
                            TextButton.icon(
                              onPressed: () => _editDiploma(index),
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Modifier'),
                            ),
                            TextButton.icon(
                              onPressed: () => _removeDiploma(index),
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              label: const Text('Supprimer'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
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

  Widget _buildApplicationsView() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [_buildCollapsingAppBar('')];
      },
      body: StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('applications')
          .where('userId', isEqualTo: userSession.userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final applications = (snapshot.data?.docs ?? []).toList();
        applications.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = (aData['appliedAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
          final bTime = (bData['appliedAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
          return bTime.compareTo(aTime);
        });
        final appliedApplications = applications.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString().toLowerCase();
          return status == 'accepted';
        }).toList();
      if (appliedApplications.isEmpty) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.send_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('Aucune candidature', style: TextStyle(color: Colors.grey)),
              SizedBox(height: 8),
              Text('Parcourez les offres et postulez', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: appliedApplications.length,
        itemBuilder: (context, index) {
          final data = appliedApplications[index].data() as Map<String, dynamic>;
          final status = data['status'] ?? 'pending';
            final statusColor = status == 'sent' 
                ? Colors.green 
                : status == 'accepted' 
                    ? Colors.blue 
                    : Colors.orange;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: ListTile(
                leading: const Icon(Icons.work, color: Color(0xFF4CAF50)),
                title: Text(data['offerTitle'] ?? 'Offre inconnue', style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text('Statut: ${status == 'sent' ? 'Envoyée' : status == 'accepted' ? 'Acceptée' : 'En attente'}'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status == 'sent' ? 'Envoyée' : status == 'accepted' ? 'Acceptée' : 'En attente',
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          },
        );
      },
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

      final Uri geminiUri = Uri.parse('https://generativelanguage.googleapis.com/v1beta2/models/gemini-1.5-flash:generateText?key=$_gcpApiKey');
      final Uri bisonUri = Uri.parse('https://generativelanguage.googleapis.com/v1beta2/models/text-bison-001:generateText?key=$_gcpApiKey');
      Future<http.Response> postTextGeneration(Uri uri) {
        return http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'prompt': {
              'text': prompt,
            },
          }),
        );
      }

      var response = await postTextGeneration(geminiUri);
      if (response.statusCode == 404) {
        response = await postTextGeneration(bisonUri);
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        String extractGeneratedText(dynamic content) {
          if (content == null) return '';
          if (content is String) return content.trim();
          if (content is Map<String, dynamic>) {
            if (content['parts'] is List) {
              return (content['parts'] as List)
                  .map((part) => extractGeneratedText(part['text']))
                  .where((text) => text.isNotEmpty)
                  .join(' ')
                  .trim();
            }
            return content.values
                .map(extractGeneratedText)
                .where((text) => text.isNotEmpty)
                .join(' ')
                .trim();
          }
          if (content is List) {
            return content
                .map(extractGeneratedText)
                .where((text) => text.isNotEmpty)
                .join(' ')
                .trim();
          }
          return '';
        }

        String generatedText = '';
        if (data['candidates'] is List && data['candidates'].isNotEmpty) {
          final candidate = data['candidates'][0];
          generatedText = extractGeneratedText(candidate['content'] ?? candidate['output'] ?? candidate);
        }
        if (generatedText.isEmpty && data['output'] is Map<String, dynamic>) {
          generatedText = extractGeneratedText((data['output'] as Map<String, dynamic>)['content']);
        }
        if (generatedText.isEmpty && data['content'] != null) {
          generatedText = extractGeneratedText(data['content']);
        }

        if (generatedText.isNotEmpty) {
          setState(() {
            _aboutController.text = generatedText;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Texte généré avec succès')),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucun texte généré. Veuillez réessayer.')),
          );
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

class _ProfileSection {
  final String name;
  final double completed;
  _ProfileSection({required this.name, required this.completed});
}

class _ProfileDonutChartPainter extends CustomPainter {
  final double completion;
  final List<_ProfileSection> sections;

  _ProfileDonutChartPainter({required this.completion, required this.sections});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 10;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 20;

    final colors = [
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFFF44336),
    ];

    double startAngle = -pi / 2;
    for (int i = 0; i < sections.length; i++) {
      final sweep = 2 * pi / sections.length * sections[i].completed;
      paint.color = colors[i % colors.length].withOpacity(sections[i].completed > 0 ? 1 : 0.3);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, paint);
      startAngle += 2 * pi / sections.length;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _SemiCircleProgressPainter extends CustomPainter {
  final double value;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _SemiCircleProgressPainter({
    required this.value,
    this.backgroundColor = const Color(0x334CAF50),
    this.progressColor = const Color(0xFF4CAF50),
    this.strokeWidth = 8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - strokeWidth / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    paint.color = backgroundColor;
    canvas.drawCircle(center, radius, paint);

    final clampedValue = value.clamp(0.0, 1.0);
    paint.color = progressColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * clampedValue,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}