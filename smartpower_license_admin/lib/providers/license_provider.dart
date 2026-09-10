import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/license_model.dart';
import '../services/license_admin_service.dart';

final licenseAdminServiceProvider = Provider<LicenseAdminService>((ref) {
  return LicenseAdminService();
});

enum LicenseFilter { all, active, bound, expiringSoon, inactive }

class LicenseState {
  final List<LicenseModel> licenses;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final LicenseFilter filter;

  LicenseState({
    this.licenses = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.filter = LicenseFilter.all,
  });

  LicenseState copyWith({
    List<LicenseModel>? licenses,
    bool? isLoading,
    String? error,
    String? searchQuery,
    LicenseFilter? filter,
  }) {
    return LicenseState(
      licenses: licenses ?? this.licenses,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      filter: filter ?? this.filter,
    );
  }

  List<LicenseModel> get filteredLicenses {
    return licenses.where((lic) {
      // 1. Search Query filter
      final matchesSearch = searchQuery.isEmpty ||
          lic.clientName.toLowerCase().contains(searchQuery.toLowerCase()) ||
          lic.licenseKey.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (lic.boundHwid?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);

      if (!matchesSearch) return false;

      // 2. Status filter
      switch (filter) {
        case LicenseFilter.active:
          return lic.isActive && !lic.isExpired;
        case LicenseFilter.bound:
          return lic.isBound;
        case LicenseFilter.expiringSoon:
          return lic.isActive && !lic.isExpired && lic.daysRemaining <= 15;
        case LicenseFilter.inactive:
          return !lic.isActive || lic.isExpired;
        case LicenseFilter.all:
          return true;
      }
    }).toList();
  }

  int get totalCount => licenses.length;
  int get activeCount => licenses.where((l) => l.isActive && !l.isExpired).length;
  int get boundCount => licenses.where((l) => l.isBound).length;
  int get expiringSoonCount =>
      licenses.where((l) => l.isActive && !l.isExpired && l.daysRemaining <= 15).length;
}

class LicenseNotifier extends StateNotifier<LicenseState> {
  final LicenseAdminService _service;

  LicenseNotifier(this._service) : super(LicenseState()) {
    loadLicenses();
  }

  Future<void> loadLicenses() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _service.fetchLicenses();
      state = state.copyWith(licenses: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setFilter(LicenseFilter filter) {
    state = state.copyWith(filter: filter);
  }

  Future<void> unbindHWID(String licenseId) async {
    await _service.unbindHWID(licenseId);
    await loadLicenses();
  }

  Future<void> toggleActiveStatus(String licenseId, bool isActive) async {
    await _service.toggleActiveStatus(licenseId, isActive);
    await loadLicenses();
  }

  Future<void> extendSubscription(String licenseId, DateTime currentExpiry, int additionalDays) async {
    await _service.extendSubscription(licenseId, currentExpiry, additionalDays);
    await loadLicenses();
  }

  Future<String> assignEmergencyCode(String licenseId) async {
    final code = await _service.assignEmergencyCode(licenseId);
    await loadLicenses();
    return code;
  }

  Future<void> deleteLicense(String licenseId) async {
    await _service.deleteLicense(licenseId);
    await loadLicenses();
  }
}

final licenseProvider =
    StateNotifierProvider<LicenseNotifier, LicenseState>((ref) {
  final service = ref.watch(licenseAdminServiceProvider);
  return LicenseNotifier(service);
});
