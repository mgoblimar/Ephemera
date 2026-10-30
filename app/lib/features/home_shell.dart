import 'package:flutter/material.dart';

import 'package:ephemera_ai/features/archive/archive_screen.dart';
import 'package:ephemera_ai/features/library/library_screen.dart';

/// Bottom navigation between journals and the scrap archive.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [LibraryScreen(), ArchiveScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Journals',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_outlined),
            label: 'Scraps',
          ),
        ],
      ),
    );
  }
}
