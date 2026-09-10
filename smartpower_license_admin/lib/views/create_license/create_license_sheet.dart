import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/license_provider.dart';

class CreateLicenseSheet extends ConsumerStatefulWidget {
  const CreateLicenseSheet({super.key});

  @override
  ConsumerState<CreateLicenseSheet> createState() => _CreateLicenseSheetState();
}

class _CreateLicenseSheetState extends ConsumerState<CreateLicenseSheet> {
  final _nameController = TextEditingController();
  int _selectedDays = 365; // 1 Year default
  int _selectedOfflineDays = 30;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _durations = [
    {'label': '15 يوماً (تجريبي)', 'days': 15},
    {'label': '1 شهر', 'days': 30},
    {'label': '6 أشهر', 'days': 180},
    {'label': '1 سنة (موصى به)', 'days': 365},
    {'label': '3 سنوات', 'days': 1095},
    {'label': '5 سنوات (دائم)', 'days': 1825},
  ];

  final List<int> _offlineLimits = [14, 30, 60, 90, 180];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم المحطة أو المشترك')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final service = ref.read(licenseAdminServiceProvider);
      final newLic = await service.createLicense(
        clientName: name,
        durationDays: _selectedDays,
        maxOfflineDays: _selectedOfflineDays,
      );

      await ref.read(licenseProvider.notifier).loadLicenses();

      if (mounted) {
        Navigator.pop(context);
        _showSuccessDialog(newLic.clientName, newLic.licenseKey, _selectedDays);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إنشاء الترخيص: $e'), backgroundColor: AppConstants.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(String clientName, String key, int days) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppConstants.success, size: 28),
            const SizedBox(width: 8),
            Text('تم إنشاء الترخيص بنجاح', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اسم المحطة: $clientName', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: SelectableText(
                key,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppConstants.primary,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'أرسل هذا المفتاح للعميل لإدخاله في شاشة التفعيل على كمبيوتر المحطة.',
              style: GoogleFonts.cairo(fontSize: 12, color: AppConstants.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ المفتاح')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text('نسخ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final shareText = '''
مرحباً بك في نظام SmartPower ERP ⚡
تم تفعيل اشتراكك بنجاح.

📌 اسم المحطة: $clientName
🔑 مفتاح الترخيص: $key
⏱️ مدة الاشتراك: $days يوماً

يرجى إدخال المفتاح في شاشة التفعيل عند فتح البرنامج.
''';
              Share.share(shareText, subject: 'مفتاح ترخيص SmartPower ERP');
            },
            icon: const Icon(Icons.share, size: 18),
            label: Text('مشاركة عبر واتساب', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 24,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
            Row(
              children: [
                const Icon(Icons.add_card_rounded, color: AppConstants.primary, size: 26),
                const SizedBox(width: 8),
                Text(
                  'توليد مفتاح ترخيص جديد',
                  style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Client Name Field
            Text('اسم المحطة / العميل:', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'مثال: محطة النور لتوليد الكهرباء',
                prefixIcon: Icon(Icons.business_rounded, color: AppConstants.textMuted),
              ),
            ),
            const SizedBox(height: 20),

            // Duration Choices
            Text('مدة الاشتراك:', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _durations.map((d) {
                final isSelected = _selectedDays == d['days'];
                return ChoiceChip(
                  label: Text(
                    d['label'] as String,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : AppConstants.textMain,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppConstants.primary,
                  backgroundColor: const Color(0xFFF1F5F9),
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedDays = d['days'] as int);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Offline Days Limit
            Text('مهلة العمل أوفلاين بدون إنترنت (أيام):',
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: _offlineLimits.map((limit) {
                final isSelected = _selectedOfflineDays == limit;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () => setState(() => _selectedOfflineDays = limit),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppConstants.primaryLight : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppConstants.primary : AppConstants.border,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$limit يوم',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? Colors.white : AppConstants.textMain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submit,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.vpn_key_rounded),
                label: Text(
                  _isLoading ? 'جاري التوليد والربط...' : 'توليد المفتاح الآن',
                  style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
