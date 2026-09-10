import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../models/license_model.dart';
import '../../providers/license_provider.dart';

class LicenseDetailSheet extends ConsumerStatefulWidget {
  final LicenseModel license;

  const LicenseDetailSheet({super.key, required this.license});

  @override
  ConsumerState<LicenseDetailSheet> createState() => _LicenseDetailSheetState();
}

class _LicenseDetailSheetState extends ConsumerState<LicenseDetailSheet> {
  bool _isLoading = false;

  Future<void> _unbindHWID() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('تأكيد فك قيد الجهاز', style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'هل أنت متأكد من فك ربط هذا المفتاح بالكمبيوتر الحالي؟\n\nسيتمكن العميل من تشغيل واستخدام المفتاح على كمبيوتر جديد فوراً.',
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، فك القيد'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await ref.read(licenseProvider.notifier).unbindHWID(widget.license.id);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم فك قيد العتاد بنجاح، المفتاح متاح الآن لأي جهاز جديد')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _extendSubscription(int days) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(licenseProvider.notifier).extendSubscription(
            widget.license.id,
            widget.license.expiresAt,
            days,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تمديد الاشتراك بنجاح بـ $days يوماً')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateEmergencyCode() async {
    setState(() => _isLoading = true);
    try {
      final code = await ref.read(licenseProvider.notifier).assignEmergencyCode(widget.license.id);
      if (mounted) {
        Navigator.pop(context);
        _showEmergencyCodeDialog(code);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEmergencyCodeDialog(String code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.flash_on_rounded, color: AppConstants.warning, size: 28),
            const SizedBox(width: 8),
            Text('كود طوارئ أوفلاين جديد', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المحطة: ${widget.license.clientName}', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppConstants.warning,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'صلاحية هذا الكود: 15 يوماً من الآن لتشغيل النظام بدون إنترنت.',
              style: GoogleFonts.cairo(fontSize: 12, color: AppConstants.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الكود')));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text('نسخ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.warning),
            onPressed: () {
              final shareText = '''
كود طوارئ SmartPower ERP ⚡
المحطة: ${widget.license.clientName}

📌 كود الطوارئ: $code
صلاحية الكود: 15 يوماً للعمل بدون اتصال بالإنترنت.
''';
              Share.share(shareText, subject: 'كود طوارئ أوفلاين');
            },
            icon: const Icon(Icons.share, size: 18),
            label: Text('مشاركة واتساب', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSuspend() async {
    setState(() => _isLoading = true);
    try {
      final newStatus = !widget.license.isActive;
      await ref.read(licenseProvider.notifier).toggleActiveStatus(widget.license.id, newStatus);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newStatus ? 'تم تفعيل الاشتراك' : 'تم إيقاف الاشتراك')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteLicense() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('حذف الترخيص نهائياً', style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 16)),
        content: const Text('هل أنت متأكد من حذف سجل هذا الترخيص من السيرفر؟ لن يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await ref.read(licenseProvider.notifier).deleteLicense(widget.license.id);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الترخيص')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lic = widget.license;
    final isExpired = lic.isExpired;
    final isBound = lic.isBound;

    return Container(
      padding: const EdgeInsets.only(top: 24, left: 20, right: 20, bottom: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Title & Status Badge
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lic.clientName,
                          style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900)),
                      Text('أنشئ في: ${AppFormatters.formatDate(lic.createdAt)}',
                          style: GoogleFonts.cairo(fontSize: 11, color: AppConstants.textMuted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: !lic.isActive
                        ? Colors.red.shade50
                        : isExpired
                            ? Colors.amber.shade50
                            : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: !lic.isActive
                          ? Colors.red.shade200
                          : isExpired
                              ? Colors.amber.shade200
                              : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Text(
                    !lic.isActive
                        ? 'موقوف'
                        : isExpired
                            ? 'منتهي الصلاحية'
                            : 'نشط (${lic.daysRemaining} يوم)',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
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
            const SizedBox(height: 20),

            // License Key Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('مفتاح الترخيص (License Key)',
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.primaryLight)),
                        const SizedBox(height: 2),
                        SelectableText(
                          lic.licenseKey,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppConstants.primary,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: lic.licenseKey));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ المفتاح')));
                    },
                    icon: const Icon(Icons.copy, color: AppConstants.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Bound HWID Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppConstants.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الكمبيوتر المرتبط (HWID)',
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.textMuted)),
                        const SizedBox(height: 2),
                        Text(
                          isBound ? lic.boundHwid! : 'غير مقيد بجهاز (متاح للتفعيل على أي كمبيوتر)',
                          style: TextStyle(
                            fontFamily: isBound ? 'monospace' : null,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isBound ? AppConstants.textMain : AppConstants.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isBound)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFFBEB),
                        foregroundColor: AppConstants.warning,
                        elevation: 0,
                        side: const BorderSide(color: Color(0xFFFDE68A)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: _isLoading ? null : _unbindHWID,
                      icon: const Icon(Icons.lock_open_rounded, size: 16),
                      label: Text('فك القيد', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Subscription Dates Grid
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile('تاريخ البدء', AppFormatters.formatDate(lic.startsAt), Icons.calendar_today_rounded),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInfoTile('تاريخ الانتهاء', AppFormatters.formatDate(lic.expiresAt), Icons.event_available_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile('مهلة الأوفلاين', '${lic.maxOfflineDays} يوماً', Icons.cloud_off_rounded),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInfoTile(
                    'آخر نبضة أونلاين',
                    lic.lastHeartbeatAt != null ? AppFormatters.formatDateTime(lic.lastHeartbeatAt) : 'لم يتصل بعد',
                    Icons.wifi_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Text('العمليات والإجراءات السريعة:', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),

            // Extend Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _extendSubscription(30),
                    child: Text('+ 1 شهر', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _extendSubscription(180),
                    child: Text('+ 6 أشهر', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _extendSubscription(365),
                    child: Text('+ 1 سنة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Emergency Code Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.warning,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isLoading ? null : _generateEmergencyCode,
                icon: const Icon(Icons.flash_on_rounded, size: 20),
                label: Text('توليد كود طوارئ أوفلاين (15 يوماً)', style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),

            // Share WhatsApp
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final text = '''
بيانات ترخيص SmartPower ERP ⚡
المحطة: ${lic.clientName}

🔑 مفتاح الترخيص: ${lic.licenseKey}
📅 تاريخ الانتهاء: ${AppFormatters.formatDate(lic.expiresAt)}
⏱️ الأيام المتبقية: ${lic.daysRemaining} يوم
''';
                  Share.share(text);
                },
                icon: const Icon(Icons.share, size: 20),
                label: Text('مشاركة الترخيص عبر الواتساب', style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),

            // Suspend & Delete
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: lic.isActive ? AppConstants.danger : AppConstants.success,
                    ),
                    onPressed: _isLoading ? null : _toggleSuspend,
                    icon: Icon(lic.isActive ? Icons.block : Icons.play_arrow),
                    label: Text(lic.isActive ? 'إيقاف مؤقت' : 'تفعيل الاشتراك', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading ? null : _deleteLicense,
                  icon: const Icon(Icons.delete_outline, color: AppConstants.danger),
                  tooltip: 'حذف الترخيص',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppConstants.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600, color: AppConstants.textMuted)),
                Text(value, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w800, color: AppConstants.textMain)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
