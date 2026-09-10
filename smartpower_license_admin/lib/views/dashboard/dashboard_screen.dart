import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../models/license_model.dart';
import '../../providers/license_provider.dart';
import '../create_license/create_license_sheet.dart';
import '../license_detail/license_detail_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _openCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateLicenseSheet(),
    );
  }

  void _openDetailSheet(BuildContext context, LicenseModel license) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LicenseDetailSheet(license: license),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(licenseProvider);

    return Scaffold(
      backgroundColor: AppConstants.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, color: AppConstants.primaryLight, size: 24),
            const SizedBox(width: 6),
            Text(AppConstants.appTitle, style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => ref.read(licenseProvider.notifier).loadLicenses(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث البيانات',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppConstants.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () => _openCreateSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: Text('ترخيص جديد', style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(licenseProvider.notifier).loadLicenses(),
        child: CustomScrollView(
          slivers: [
            // KPI Stats Cards Grid
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildKpiCard(
                            title: 'إجمالي المحطات',
                            count: state.totalCount,
                            icon: Icons.domain_rounded,
                            color: AppConstants.primary,
                            bgColor: const Color(0xFFEFF6FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildKpiCard(
                            title: 'الاشتراكات النشطة',
                            count: state.activeCount,
                            icon: Icons.check_circle_outline_rounded,
                            color: AppConstants.success,
                            bgColor: const Color(0xFFECFDF5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildKpiCard(
                            title: 'الأجهزة المقيدة',
                            count: state.boundCount,
                            icon: Icons.laptop_windows_rounded,
                            color: const Color(0xFF6366F1),
                            bgColor: const Color(0xFFEEF2FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildKpiCard(
                            title: 'تنتهي قريباً',
                            count: state.expiringSoonCount,
                            icon: Icons.alarm_rounded,
                            color: AppConstants.warning,
                            bgColor: const Color(0xFFFFFBEB),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar & Filter Chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    TextField(
                      onChanged: (val) => ref.read(licenseProvider.notifier).setSearchQuery(val),
                      decoration: InputDecoration(
                        hintText: 'ابحث باسم المحطة، المفتاح، أو بصمة العتاد (HWID)...',
                        prefixIcon: const Icon(Icons.search_rounded, color: AppConstants.textMuted),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: state.searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => ref.read(licenseProvider.notifier).setSearchQuery(''),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(ref, 'الكل (${state.totalCount})', LicenseFilter.all, state.filter),
                          _buildFilterChip(ref, 'النشطة (${state.activeCount})', LicenseFilter.active, state.filter),
                          _buildFilterChip(ref, 'المقيدة (${state.boundCount})', LicenseFilter.bound, state.filter),
                          _buildFilterChip(ref, 'تنتهي قريباً (${state.expiringSoonCount})', LicenseFilter.expiringSoon, state.filter),
                          _buildFilterChip(ref, 'الموقوفة', LicenseFilter.inactive, state.filter),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // License Cards List
            if (state.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppConstants.danger, size: 48),
                      const SizedBox(height: 12),
                      Text('تعذر تحميل البيانات من السحابة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(state.error!, style: GoogleFonts.cairo(fontSize: 12, color: AppConstants.textMuted)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => ref.read(licenseProvider.notifier).loadLicenses(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              )
            else if (state.filteredLicenses.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400, size: 56),
                      const SizedBox(height: 12),
                      Text('لا توجد تراخيص مطابقة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('اضغط على "ترخيص جديد" لتوليد مفتاح أول محطة', style: GoogleFonts.cairo(fontSize: 12, color: AppConstants.textMuted)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final lic = state.filteredLicenses[index];
                      return _buildLicenseItemCard(context, lic);
                    },
                    childCount: state.filteredLicenses.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppConstants.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: AppConstants.textMuted)),
                Text(
                  AppFormatters.formatNumber(count),
                  style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AppConstants.textMain),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(WidgetRef ref, String label, LicenseFilter filter, LicenseFilter activeFilter) {
    final isSelected = filter == activeFilter;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : AppConstants.textMain,
          ),
        ),
        selected: isSelected,
        selectedColor: AppConstants.primary,
        backgroundColor: Colors.white,
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (_) => ref.read(licenseProvider.notifier).setFilter(filter),
      ),
    );
  }

  Widget _buildLicenseItemCard(BuildContext context, LicenseModel lic) {
    final isExpired = lic.isExpired;
    final isBound = lic.isBound;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: !lic.isActive
              ? Colors.red.shade200
              : isExpired
                  ? Colors.amber.shade200
                  : AppConstants.border,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openDetailSheet(context, lic),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Client Name & Status Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: !lic.isActive
                            ? Colors.red.shade50
                            : isExpired
                                ? Colors.amber.shade50
                                : const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        !lic.isActive
                            ? Icons.block_rounded
                            : isExpired
                                ? Icons.timer_off_rounded
                                : Icons.electric_bolt_rounded,
                        size: 20,
                        color: !lic.isActive
                            ? AppConstants.danger
                            : isExpired
                                ? AppConstants.warning
                                : AppConstants.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lic.clientName,
                            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            lic.licenseKey,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppConstants.primaryLight,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: !lic.isActive
                            ? Colors.red.shade50
                            : isExpired
                                ? Colors.amber.shade50
                                : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        !lic.isActive
                            ? 'موقوف'
                            : isExpired
                                ? 'منتهي'
                                : '${lic.daysRemaining} يوم',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: !lic.isActive
                              ? AppConstants.danger
                              : isExpired
                                  ? AppConstants.warning
                                  : AppConstants.success,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppConstants.border),
                const SizedBox(height: 10),

                // Device Binding info & expiry
                Row(
                  children: [
                    Icon(
                      isBound ? Icons.laptop_windows_rounded : Icons.lock_open_rounded,
                      size: 15,
                      color: isBound ? AppConstants.textMuted : AppConstants.success,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isBound ? 'مقيد: ${lic.boundHwid}' : 'متاح للربط على أي جهاز',
                        style: TextStyle(
                          fontFamily: isBound ? 'monospace' : null,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isBound ? AppConstants.textMuted : AppConstants.success,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ينتهي: ${AppFormatters.formatDate(lic.expiresAt)}',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppConstants.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
