import 'dart:convert';
// import 'dart:io';
// import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:pdf/pdf.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'package:printing/printing.dart';
import '../auth_service.dart';
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
            final status = data?['status'] as String? ?? 'pending';
            final email = data?['email'] ?? 'Entreprise';
            final name = data?['name'] ?? email;

            Color statusColor;
            String statusLabel;
            switch (status) {
              case 'approved':
                statusColor = Colors.green;
                statusLabel = 'Validé';
              case 'rejected':
                statusColor = Colors.red;
                statusLabel = 'Rejeté';
              default:
                statusColor = Colors.orange;
                statusLabel = 'En attente';
            }

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: ListTile(
                leading: const Icon(Icons.business, color: Color(0xFF00BCD4)),
                title: Text(name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(email),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.visibility, color: Colors.blue),
                  onPressed: () => _openCompanyDetailSheet(company.id, data),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openCompanyDetailSheet(String companyId, Map<String, dynamic>? data) {
    final documentUrl = data?['documentUrl'] as String?;
    final status = data?['status'] as String? ?? 'pending';
    final rejectionReason = data?['rejectionReason'] as String? ?? '';
    final email = data?['email'] ?? '';
    final name = data?['name'] ?? '';
    final rejectionController = TextEditingController(text: rejectionReason);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
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
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  email,
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Document d\'enregistrement',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (documentUrl != null && documentUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _showDocumentPreview(documentUrl);
                    },
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _isImageUrl(documentUrl)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                documentUrl,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 200,
                                    color: Colors.grey[200],
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                          SizedBox(height: 8),
                                          Text('Impossible de charger le document'),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          : InkWell(
                              onTap: () {
                                _showDocumentPreview(documentUrl);
                              },
                              child: Container(
                                height: 200,
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.description, size: 48, color: Colors.grey),
                                      SizedBox(height: 8),
                                      Text('Ouvrir le document'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  )
                else
                  Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Text('Aucun document disponible'),
                    ),
                  ),
                const SizedBox(height: 16),
                if (status == 'pending') ...[
                  const Text(
                    'Motif de rejet (optionnel)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: rejectionController,
                    decoration: InputDecoration(
                      hintText: 'Raison du rejet...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : () async {
                            await _reviewCompany(companyId, 'approved');
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Valider'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  final reason = rejectionController.text.trim();
                                  if (reason.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Veuillez saisir un motif de rejet',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  await _reviewCompany(companyId, 'rejected', reason);
                                  if (context.mounted) Navigator.pop(context);
                                },
                          icon: const Icon(Icons.close),
                          label: const Text('Rejeter'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: status == 'approved'
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          status == 'approved'
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: status == 'approved' ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            status == 'approved'
                                ? 'Compte validé'
                                : 'Compte rejeté : $rejectionReason',
                            style: TextStyle(
                              color: status == 'approved'
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _reviewCompany(String companyId, String decision, [String? reason]) async {
    setState(() => _isLoading = true);
    try {
      final updates = <String, dynamic>{
        'status': decision,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': userSession.userId,
      };

      if (decision == 'rejected') {
        updates['rejectionReason'] = reason ?? '';
      }

      await firestore.collection('users').doc(companyId).update(updates);

      final companyDoc = await firestore.collection('users').doc(companyId).get();
      final companyData = companyDoc.data();
      final companyFcmToken = companyData?['fcmToken'] as String?;
      final companyName = companyData?['name'] ?? 'Entreprise';

      if (companyFcmToken != null && companyFcmToken.isNotEmpty) {
        await _sendCompanyNotification(
          companyFcmToken,
          decision == 'approved' ? 'Compte validé' : 'Compte rejeté',
          decision == 'approved'
              ? 'Votre compte entreprise a été validé par l\'administrateur.'
              : 'Votre compte entreprise a été rejeté : ${reason ?? "Raison non spécifiée"}',
        );
      }

      await firestore.collection('company_notifications').add({
        'userId': companyId,
        'title': decision == 'approved' ? 'Compte validé' : 'Compte rejeté',
        'body': decision == 'approved'
            ? 'Votre compte entreprise a été validé par l\'administrateur.'
            : 'Votre compte entreprise a été rejeté : ${reason ?? "Raison non spécifiée"}',
        'type': decision == 'approved' ? 'validation_approved' : 'validation_rejected',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'approved'
                  ? 'Entreprise validée'
                  : 'Entreprise rejetée',
            ),
          ),
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

  Future<void> _sendCompanyNotification(
    String token,
    String title,
    String body,
  ) async {
    try {
      final response = await http.post(
            Uri.parse('http://192.168.170.89/VERA/send_notification.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'title': title,
          'body': body,
        }),
      );
    } catch (e) {
    }
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  void _showDocumentPreview(String url) {
    if (!_isImageUrl(url)) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.network(
            url,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            },
          ),
        ),
      ),
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

