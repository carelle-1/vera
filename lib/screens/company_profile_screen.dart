import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../auth_service.dart';

class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key, required this.companyUserId});

  final String companyUserId;

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Widget _buildDefaultCompanyLogo(String company, {double size = 50}) {
    return Image.asset(
      'assets/logo_defaut.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  Widget _buildProfileField(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label :',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF4CAF50),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(widget.companyUserId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: _companyAppBar(
              logoUrl: null,
              name: '',
              slogan: '',
              descriptionPreview: '',
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError ||
            !snapshot.hasData ||
            !snapshot.data!.exists) {
          return Scaffold(
            appBar: _companyAppBar(
              logoUrl: null,
              name: '',
              slogan: '',
              descriptionPreview: '',
            ),
            body: const Center(child: Text('Informations non disponibles')),
          );
        }

        final info = snapshot.data!.data() as Map<String, dynamic>? ?? {};

        final logoUrl = info['companyLogoUrl'] as String?;
        final name = (info['name'] ?? '').toString().trim();
        final slogan = (info['slogan'] ?? '').toString().trim();
        final shortDesc = (info['shortDescription'] ?? '').toString().trim();
        final about = (info['about'] ?? '').toString().trim();
        final creationYear = (info['creationYear'] ?? '').toString().trim();
        final companyType = (info['companyType'] ?? '').toString().trim();
        final sector = (info['sector'] ?? '').toString().trim();
        final subSector = (info['subSector'] ?? '').toString().trim();
        final companySize = (info['companySize'] ?? '').toString().trim();
        final legalStatus = (info['legalStatus'] ?? '').toString().trim();
        final registrationNumber =
            (info['registrationNumber'] ?? '').toString().trim();
        final taxId = (info['taxId'] ?? '').toString().trim();
        final companyCountry = (info['country'] ?? '').toString().trim();
        final region = (info['region'] ?? '').toString().trim();
        final city = (info['city'] ?? '').toString().trim();
        final district = (info['district'] ?? '').toString().trim();
        final address = (info['address'] ?? '').toString().trim();
        final professionalEmail =
            (info['professionalEmail'] ?? '').toString().trim();
        final phone = (info['phone'] ?? '').toString().trim();
        final website = (info['website'] ?? '').toString().trim();
        final whatsapp = (info['whatsapp'] ?? '').toString().trim();
        final phoneSecondary =
            (info['phoneSecondary'] ?? '').toString().trim();
        final hrContact = (info['hrContact'] ?? '').toString().trim();
        final recruitmentEmail =
            (info['recruitmentEmail'] ?? '').toString().trim();
        final openingHours = (info['openingHours'] ?? '').toString().trim();
        final activities = (info['activities'] ?? '').toString().trim();
        final products = (info['products'] ?? '').toString().trim();
        final services = (info['services'] ?? '').toString().trim();
        final expertise = (info['expertise'] ?? '').toString().trim();
        final technologies = (info['technologies'] ?? '').toString().trim();
        final mainMarkets = (info['mainMarkets'] ?? '').toString().trim();
        final geographicCoverage =
            (info['geographicCoverage'] ?? '').toString().trim();
        final targetClients = (info['targetClients'] ?? '').toString().trim();
        final projects = (info['projects'] ?? '').toString().trim();
        final achievements = (info['achievements'] ?? '').toString().trim();

        final description = about;
        final descriptionPreview = description.length > 80
            ? '${description.substring(0, 80)}...'
            : description;

        return Scaffold(
          appBar: _companyAppBar(
            logoUrl: logoUrl,
            name: name,
            slogan: slogan,
            descriptionPreview: descriptionPreview,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (slogan.isNotEmpty) ...[
                  Text(
                    slogan,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (shortDesc.isNotEmpty) ...[
                  const Text('Description',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(shortDesc),
                  const SizedBox(height: 12),
                ],
                if (about.isNotEmpty) ...[
                  const Text('À propos',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(about),
                  const SizedBox(height: 12),
                ],
                if (creationYear.isNotEmpty ||
                    companyType.isNotEmpty ||
                    sector.isNotEmpty ||
                    subSector.isNotEmpty ||
                    legalStatus.isNotEmpty ||
                    companySize.isNotEmpty ||
                    registrationNumber.isNotEmpty ||
                    taxId.isNotEmpty ||
                    website.isNotEmpty) ...[
                  _buildProfileSectionHeader('Informations générales'),
                  _buildProfileField('Année de création', creationYear),
                  _buildProfileField('Type d\'entreprise', companyType),
                  _buildProfileField('Secteur d\'activité', sector),
                  _buildProfileField('Sous-secteur', subSector),
                  _buildProfileField('Statut juridique', legalStatus),
                  _buildProfileField('Taille', companySize),
                  _buildProfileField('Numéro d\'immatriculation',
                      registrationNumber),
                  _buildProfileField('Numéro fiscal', taxId),
                  _buildProfileField('Site web', website),
                ],
                if (address.isNotEmpty ||
                    city.isNotEmpty ||
                    region.isNotEmpty ||
                    companyCountry.isNotEmpty ||
                    district.isNotEmpty) ...[
                  _buildProfileSectionHeader('Localisation'),
                  _buildProfileField('Adresse', address),
                  _buildProfileField('Ville', city),
                  _buildProfileField('Région', region),
                  _buildProfileField('Pays', companyCountry),
                  _buildProfileField('Quartier', district),
                ],
                if (professionalEmail.isNotEmpty ||
                    phone.isNotEmpty ||
                    whatsapp.isNotEmpty ||
                    phoneSecondary.isNotEmpty ||
                    hrContact.isNotEmpty ||
                    recruitmentEmail.isNotEmpty) ...[
                  _buildProfileSectionHeader('Coordnées'),
                  _buildProfileField('Email professionnelle', professionalEmail),
                  _buildProfileField('Téléphone', phone),
                  _buildProfileField('WhatsApp', whatsapp),
                  _buildProfileField('Téléphone secondaire', phoneSecondary),
                  _buildProfileField('Contact RH', hrContact),
                  _buildProfileField('Email recrutement', recruitmentEmail),
                ],
                if (openingHours.isNotEmpty ||
                    activities.isNotEmpty ||
                    products.isNotEmpty ||
                    services.isNotEmpty ||
                    expertise.isNotEmpty ||
                    technologies.isNotEmpty) ...[
                  _buildProfileSectionHeader('Activités & Métier'),
                  _buildProfileField('Horaires d\'ouverture', openingHours),
                  _buildProfileField('Activités de l\'entreprise', activities),
                  _buildProfileField('Produits', products),
                  _buildProfileField('Services', services),
                  _buildProfileField('Domaines d\'expertise', expertise),
                  _buildProfileField('Technologies', technologies),
                ],
                if (mainMarkets.isNotEmpty ||
                    geographicCoverage.isNotEmpty ||
                    targetClients.isNotEmpty) ...[
                  _buildProfileSectionHeader('Marché'),
                  _buildProfileField('Principaux marchés', mainMarkets),
                  _buildProfileField('Zone géographique', geographicCoverage),
                  _buildProfileField('Clients ciblés', targetClients),
                ],
                if (projects.isNotEmpty || achievements.isNotEmpty) ...[
                  _buildProfileSectionHeader('Projets & Réalisations'),
                  _buildProfileField('Projets réalisés', projects),
                  _buildProfileField('Réalisations', achievements),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _companyAppBar({
    String? logoUrl,
    required String name,
    required String slogan,
    required String descriptionPreview,
  }) {
    final displayName = name.isNotEmpty ? name : 'Espace entreprise';
    return AppBar(
      toolbarHeight: 110,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.white,
        backgroundImage:
            logoUrl != null && logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
        child: logoUrl == null || logoUrl.isEmpty
            ? const Icon(Icons.business, size: 20, color: Color(0xFF00BCD4))
            : null,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (slogan.isNotEmpty)
            Text(
              slogan,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          if (descriptionPreview.isNotEmpty)
            Text(
              descriptionPreview,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
        ],
      ),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF81D4FA), Color(0xFF4CAF50)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }
}
