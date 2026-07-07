import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth_service.dart';

class JobseekerHomeScreen extends StatefulWidget {
  const JobseekerHomeScreen({super.key});

  @override
  State<JobseekerHomeScreen> createState() => _JobseekerHomeScreenState();
}

class _JobseekerHomeScreenState extends State<JobseekerHomeScreen> {
  int _currentIndex = 0;
  String _searchQuery = '';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Set<String> _favoriteOfferIds = {};

  Future<void> _logout() async {
    await userSession.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  int _calculateCompatibility(Map<String, dynamic> offer) {
    int score = 50;
    final skills = (offer['skills'] as List?)?.cast<String>() ?? [];
    final random = DateTime.now().millisecondsSinceEpoch % 50;
    score = 50 + random;

    return score;
  }

  void _showOfferDetails(Map<String, dynamic> data, String offerId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 150),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (data['logoUrl'] != null)
                    Image.network(
                      data['logoUrl'],
                      width: 60,
                      height: 60,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildDefaultCompanyLogo(data['company'] ?? '', size: 60),
                    )
                  else
                    _buildDefaultCompanyLogo(data['company'] ?? '', size: 60),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      data['title'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _favoriteOfferIds.contains(offerId)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: const Color(0xFF4CAF50),
                    ),
                    onPressed: () {
                      setState(() {
                        if (_favoriteOfferIds.contains(offerId)) {
                          _favoriteOfferIds.remove(offerId);
                        } else {
                          _favoriteOfferIds.add(offerId);
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Entreprise: ${data['company'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Localisation: ${data['city'] ?? ''}, ${data['country'] ?? ''}'),
              const SizedBox(height: 8),
              Text('Salaire: ${data['salary'] ?? 'Non mentionné'}'),
              const SizedBox(height: 8),
              Text(
                  'Type de contrat: ${data['contract'] ?? 'Non mentionné'}'),
              const SizedBox(height: 16),
              const Text('Description:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(data['description'] ?? ''),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                  ),
                  child: const Text('Fermer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 0
          ? AppBar(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              title: const Text('VERA - Offres'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
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
                            child: const Text('Oui'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            )
          : null,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildOffersView(),
          _buildApplicationsView(),
          _buildMessagesView(),
          _buildProfileView(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        onPressed: () {
          setState(() => _currentIndex = 3);
        },
        child: const Icon(Icons.person),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF4CAF50),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.send), label: 'Candidatures'),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messagerie'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }

  Widget _buildDefaultCompanyLogo(String company, {double size = 50}) {
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

  Widget _buildOffersView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('job_offers')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
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
            final data = offers[index].data() as Map<String, dynamic>;
            final skills = (data['skills'] as List?)?.cast<String>() ?? [];
            final skillsDisplay = skills.length > 2
                ? '${skills[0]}, ${skills[1]}, ${skills[2]}...'
                : skills.take(3).join(', ');
            final createdAt = data['createdAt'] as Timestamp?;
            final isNew = createdAt != null &&
                DateTime.now().difference(createdAt.toDate()).inDays < 7;
            final compatibility = _calculateCompatibility(data);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                      child: data['logoUrl'] != null
                          ? Image.network(
                              data['logoUrl'],
                              width: 50,
                              height: 50,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildDefaultCompanyLogo(data['company'] ?? '', size: 50),
                            )
                          : _buildDefaultCompanyLogo(data['company'] ?? '', size: 50),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isNew) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Nouveau',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                data['title'] ?? 'Sans titre',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${data['country'] ?? ''}${data['city'] != null && data['city'].toString().isNotEmpty ? ' • ${data['city']}' : ''}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (skillsDisplay.isNotEmpty)
                                Text(
                                  'Compétences: $skillsDisplay',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 70,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 50,
                                height: 50,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      value: compatibility / 100,
                                      strokeWidth: 4,
                                      backgroundColor: Colors.grey[300],
                                      color: const Color(0xFF4CAF50),
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
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Compatibilité',
                                style: TextStyle(fontSize: 9, color: Colors.black54),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (data['salary'] != null &&
                                  data['salary'].toString().isNotEmpty)
                                Text(
                                  '${data['salary']} / mois',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              if (data['salary'] != null &&
                                  data['salary'].toString().isNotEmpty &&
                                  data['contract'] != null &&
                                  data['contract'].toString().isNotEmpty)
                                const SizedBox(width: 12),
                              if (data['contract'] != null &&
                                  data['contract'].toString().isNotEmpty)
                                Text(
                                  data['contract'] == 'Temps partiel'
                                      ? 'Temps partiel'
                                      : 'Temps plein',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.visibility,
                            color: Color(0xFF4CAF50),
                          ),
                          onPressed: () {
                            _showOfferDetails(data, offers[index].id);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildApplicationsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('applications')
          .where('userId', isEqualTo: userSession.userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final applications = snapshot.data?.docs ?? [];
        if (applications.isEmpty) {
          return const Center(child: Text('Aucune candidature'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: applications.length,
          itemBuilder: (context, index) {
            final data = applications[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: ListTile(
                leading: const Icon(Icons.work, color: Color(0xFF4CAF50)),
                title: Text(data['offerTitle'] ?? 'Offre inconnue'),
                subtitle: Text('Statut: ${data['status'] ?? 'En attente'}'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMessagesView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.message, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Messagerie en développement'),
        ],
      ),
    );
  }

  Widget _buildProfileView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person, size: 80, color: Color(0xFF4CAF50)),
          SizedBox(height: 16),
          Text('Profil utilisateur'),
        ],
      ),
    );
  }
}