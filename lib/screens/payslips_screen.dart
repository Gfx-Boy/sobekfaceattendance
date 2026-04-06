import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/payslip.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  List<Payslip> _payslips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = context.read<AuthProvider>().employee;
      if (me != null) {
        _payslips = await ApiService().getPayslips(me.id);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _downloadPdf(Payslip p) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(S.paySlipTitle,
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('${S.period}: ${p.period}', style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 12),
            _pdfRow(S.employee, p.employeeName),
            _pdfRow(S.basicSalary, '\$${p.basicSalary.toStringAsFixed(2)}'),
            if (p.bonuses > 0) _pdfRow(S.bonuses, '+\$${p.bonuses.toStringAsFixed(2)}'),
            if (p.overtimePay > 0) _pdfRow(S.overtimePay, '+\$${p.overtimePay.toStringAsFixed(2)}'),
            if (p.deductions > 0) _pdfRow(S.deductions, '-\$${p.deductions.toStringAsFixed(2)}'),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.SizedBox(height: 8),
            _pdfRow(S.netSalary, '\$${p.netSalary.toStringAsFixed(2)}', bold: true),
            pw.SizedBox(height: 16),
            if (p.paymentDate != null)
              pw.Text('${S.paymentDateLabel}: ${p.paymentDate}', style: const pw.TextStyle(fontSize: 12)),
            if (p.notes.isNotEmpty)
              pw.Text('${S.notes}: ${p.notes}', style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: 'payslip_${p.period.replaceAll(' ', '_')}',
    );
  }

  pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 13)),
          pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.myPayslips)),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _payslips.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.receipt_long, size: 64, color: context.colors.textSecondary.withValues(alpha: 0.3)),
                  SizedBox(height: 12),
                  Text(S.noPayslipsFound, style: TextStyle(color: context.colors.textSecondary)),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _payslips.length,
                    itemBuilder: (_, i) => _payslipCard(_payslips[i]),
                  ),
                ),
    );
  }

  Widget _payslipCard(Payslip p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: context.colors.cardBg, borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: Border(),
        iconColor: AppTheme.primaryBlue,
        collapsedIconColor: context.colors.textSecondary,
        title: Text(p.period, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Text(
          p.paymentDate != null ? '${S.paidLabel}: ${p.paymentDate}' : S.pending,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
        trailing: Text(
          '\$${p.netSalary.toStringAsFixed(2)}',
          style: TextStyle(color: AppTheme.accentGreen, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        children: [
          _row(S.basicSalary, '\$${p.basicSalary.toStringAsFixed(2)}'),
          if (p.bonuses > 0) _row(S.bonuses, '+\$${p.bonuses.toStringAsFixed(2)}', color: AppTheme.accentGreen),
          if (p.overtimePay > 0) _row(S.overtimePay, '+\$${p.overtimePay.toStringAsFixed(2)}', color: AppTheme.accentGreen),
          if (p.deductions > 0) _row(S.deductions, '-\$${p.deductions.toStringAsFixed(2)}', color: AppTheme.checkOutRed),
          Divider(color: context.colors.surfaceBorder, height: 20),
          _row(S.netSalary, '\$${p.netSalary.toStringAsFixed(2)}', isBold: true),
          if (p.notes.isNotEmpty) ...[
            SizedBox(height: 8),
            Text('${S.noteLabel}: ${p.notes}', style: TextStyle(color: context.colors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _downloadPdf(p),
              icon: const Icon(Icons.download, size: 18),
              label: Text(S.downloadPdf),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryBlue,
                side: const BorderSide(color: AppTheme.primaryBlue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13, fontWeight: isBold ? FontWeight.w600 : FontWeight.normal)),
          Text(value, style: TextStyle(color: color ?? context.colors.textPrimary, fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }
}
