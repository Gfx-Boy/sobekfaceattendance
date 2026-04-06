import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'attendance_screen.dart';
import 'requests_screen.dart';
import 'manage_requests_screen.dart';
import 'profile_screen.dart';
import '../l10n/app_localizations.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0; // Will be set to Home in build
  bool _initialized = false;

  List<Widget> _getScreens(UserRole role) {
    if (role == UserRole.superAdmin) {
      // SuperAdmin: Profile, Home (no attendance, no requests tab)
      return const [
        ProfileScreen(),
        HomeScreen(),
      ];
    }
    if (role == UserRole.branchAdmin) {
      // BranchAdmin: Profile, Home, Manage Requests (BA doesn't make requests)
      return const [
        ProfileScreen(),
        HomeScreen(),
        ManageRequestsScreen(),
      ];
    }
    // HR & Employee: Profile, Attendance, Home, Requests
    return const [
      ProfileScreen(),
      AttendanceScreen(),
      HomeScreen(),
      RequestsScreen(),
    ];
  }

  int _homeIndex(UserRole role) {
    if (role == UserRole.superAdmin) return 1;
    if (role == UserRole.branchAdmin) return 1;
    return 2; // HR & employee
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().employee?.role ?? UserRole.employee;
    final screens = _getScreens(role);
    // Default to Home on first build
    if (!_initialized && screens.length > 1) {
      _currentIndex = _homeIndex(role);
      _initialized = true;
    }
    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: screens,
      ),
      bottomNavigationBar: _buildBottomNav(role),
    );
  }

  Widget _buildBottomNav(UserRole role) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.navBg,
        border: Border(
          top: BorderSide(color: context.colors.surfaceBorder, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: role == UserRole.superAdmin
                ? [
                    _buildNavItem(0, Icons.person_outline, Icons.person),
                    _buildHomeButton(1),
                  ]
                : role == UserRole.branchAdmin
                    ? [
                        _buildNavItem(0, Icons.person_outline, Icons.person),
                        _buildHomeButton(1),
                        _buildNavItem(2, Icons.description_outlined, Icons.description),
                      ]
                    : [
                        _buildNavItem(0, Icons.person_outline, Icons.person),
                        _buildNavItem(1, Icons.fingerprint_outlined, Icons.fingerprint),
                        _buildHomeButton(2),
                        _buildNavItem(3, Icons.description_outlined, Icons.description),
                      ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon) {
    final isActive = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        height: 44,
        child: Icon(
          isActive ? activeIcon : icon,
          color: isActive
              ? (isDark ? AppTheme.navActive : AppTheme.lightTextPrimary)
              : context.colors.textMuted,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildHomeButton(int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryBlue : context.colors.homeButtonBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive
                ? AppTheme.primaryBlue
                : context.colors.surfaceBorder,
            width: 2,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Icon(
          Icons.home_rounded,
          color: isActive ? Colors.white : context.colors.textMuted,
          size: 30,
        ),
      ),
    );
  }
}
