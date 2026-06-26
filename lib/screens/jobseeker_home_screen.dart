import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  Future<void> _logout() async {
    await userSession.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 0 ? AppBar(
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
      ) : null,
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

  Widget _buildOffersView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('job_offers').orderBy('createdAt', descending: true).snapshots(),
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
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: ListTile(
                leading: const Icon(Icons.work, color: Color(0xFF4CAF50)),
                title: Text(data['title'] ?? 'Sans titre'),
                subtitle: Text('${data['company'] ?? ''} - ${data['city'] ?? ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 8),
                          Text('Entreprise: ${data['company'] ?? ''}'),
                          Text('Lieu: ${data['city'] ?? ''}, ${data['country'] ?? ''}'),
                          const SizedBox(height: 16),
                          const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(data['description'] ?? ''),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Fermer'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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