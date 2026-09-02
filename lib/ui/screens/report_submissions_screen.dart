import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/export_history.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/screens/report_preview_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// Owner/Staff report inbox.
///
/// Owners see reports submitted by Staff. Staff see their own report history.
class ReportSubmissionsScreen extends ConsumerStatefulWidget {
  /// If true, show only the staff-to-owner submission inbox.
  /// If false, show the current user's own report history.
  final bool submissionsOnly;

  const ReportSubmissionsScreen({
    super.key,
    this.submissionsOnly = false,
  });

  @override
  ConsumerState<ReportSubmissionsScreen> createState() =>
      _ReportSubmissionsScreenState();
}

class _ReportSubmissionsScreenState
    extends ConsumerState<ReportSubmissionsScreen> {
  bool _isLoading = true;
  String? _error;
  List<ExportHistory> _reports = [];
  Map<int, String> _staffNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final reportService = ref.read(reportServiceProvider);
      final isOwner =
          ref.read(authStateProvider.notifier).hasPermission('view_report_submissions');

      final reports = widget.submissionsOnly && isOwner
          ? await reportService.getSubmittedReports()
          : await reportService.getMyReports();

      final userIds = reports
          .where((r) => r.createdBy != null)
          .map((r) => r.createdBy!)
          .toSet();

      final names = <int, String>{};
      for (final id in userIds) {
        final name = await reportService.getReportCreatorName(id);
        if (name != null && name.isNotEmpty) {
          names[id] = name;
        }
      }

      if (mounted) {
        setState(() {
          _reports = reports;
          _staffNames = names;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      debugPrint('[ReportSubmissionsScreen] load failed: $e\n$st');
      if (mounted) {
        setState(() {
          _error = 'Unable to load reports.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner =
        ref.read(authStateProvider.notifier).hasPermission('view_report_submissions');
    final title = widget.submissionsOnly && isOwner ? 'Submitted Reports' : 'My Reports';

    return Scaffold(
      appBar: AppHeader(
        title: title,
        showBackButton: true,
        actions: isOwner
            ? [
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: 'Import report',
                  onPressed: _importReport,
                ),
              ]
            : null,
      ),
      body: _buildBody(context, isOwner),
    );
  }

  Widget _buildBody(BuildContext context, bool isOwner) {
    if (_isLoading) {
      return const LoadingState(message: 'Loading reports...');
    }

    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        message: _error,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }

    if (_reports.isEmpty) {
      final isSubmissionsView = widget.submissionsOnly && isOwner;
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: isSubmissionsView
            ? 'No submitted reports yet'
            : 'No reports yet',
        message: isSubmissionsView
            ? 'Staff reports submitted to you will appear here.'
            : 'Generate and submit a report from the Reports screen, '
                'or import an external report.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final report = _reports[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _ReportCard(
              report: report,
              staffName: _staffNames[report.createdBy],
              isOwner: isOwner,
              onTap: () => _openReport(context, report),
            ),
          );
        },
      ),
    );
  }

  Future<void> _importReport() async {
    if (kIsWeb) {
      await AppDialogService.warning(
        context,
        title: 'Not supported',
        message: 'Report import is not available on the web.',
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xlsx', 'xls', 'csv'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    final name = file.name;

    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        await AppDialogService.warning(
          context,
          title: 'No file data',
          message: 'The selected file could not be read.',
        );
      }
      return;
    }

    final reportService = ref.read(reportServiceProvider);
    final imported = await reportService.importReport(
      fileName: name,
      bytes: bytes,
    );

    if (!mounted) return;

    if (imported != null) {
      await AppDialogService.success(
        context,
        title: 'Report Imported',
        message: 'The report has been saved and is ready to preview.',
      );
      _load();
    } else {
      await AppDialogService.error(
        context,
        title: 'Import Failed',
        message: 'The report could not be imported. '
            'Supported formats are PDF, Excel, and CSV.',
      );
    }
  }

  Future<void> _openReport(BuildContext context, ExportHistory report) async {
    final reportService = ref.read(reportServiceProvider);
    await reportService.markReportViewed(report.id!);

    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(report: report),
        ),
      );
      _load();
    }
  }
}

class _ReportCard extends StatelessWidget {
  final ExportHistory report;
  final String? staffName;
  final bool isOwner;
  final VoidCallback onTap;

  const _ReportCard({
    required this.report,
    this.staffName,
    required this.isOwner,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');
    final date = report.submittedAt ?? report.createdAt;

    return AppCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              _Thumbnail(report: report),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _reportTitle(report),
                      style: AppTypography.titleSmallBold(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isOwner
                          ? 'Staff: ${staffName ?? 'Unknown'}'
                          : 'Report #${report.reportNumber ?? report.id}',
                      style: AppTypography.bodySmall(context).copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(date.toLocal()),
                      style: AppTypography.bodySmall(context).copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Wrap(
                      spacing: 8,
                      children: [
                        AppStatusChip(
                          label: _statusLabel(report.status),
                          color: _statusColor(report.status, context),
                        ),
                        AppStatusChip(
                          label: report.fileFormat.toUpperCase(),
                          color: cs.primary,
                          filled: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _reportTitle(ExportHistory report) {
    final start = report.dateRangeStart;
    final end = report.dateRangeEnd;
    if (start != null && end != null) {
      final fmt = DateFormat('MMM d');
      return 'Sales Report · ${fmt.format(start)} - ${fmt.format(end)}';
    }
    return 'Sales Report #${report.reportNumber ?? report.id}';
  }

  String _statusLabel(String status) {
    return switch (status) {
      ReportStatus.generated => 'Generated',
      ReportStatus.submitted => 'Submitted',
      ReportStatus.viewed => 'Reviewed',
      ReportStatus.archived => 'Archived',
      ReportStatus.imported => 'Imported',
      _ => status,
    };
  }

  Color _statusColor(String status, BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return switch (status) {
      ReportStatus.submitted =>
        AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
      ReportStatus.viewed =>
        AppSemanticColors.resolve(AppSemanticColors.success, brightness),
      ReportStatus.archived =>
        AppSemanticColors.resolve(AppSemanticColors.neutral, brightness),
      _ => AppSemanticColors.resolve(AppSemanticColors.info, brightness),
    };
  }
}

class _Thumbnail extends StatelessWidget {
  final ExportHistory report;

  const _Thumbnail({required this.report});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final thumb = report.thumbnailPath;

    if (thumb != null && thumb.isNotEmpty && !kIsWeb) {
      final file = File(thumb);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 56,
            height: 72,
            fit: BoxFit.cover,
          ),
        );
      }
    }

    return Container(
      width: 56,
      height: 72,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _fileIcon(report.fileFormat),
        color: cs.primary,
        size: 28,
      ),
    );
  }

  IconData _fileIcon(String format) {
    return switch (format.toLowerCase()) {
      'pdf' => Icons.picture_as_pdf,
      'excel' || 'xlsx' || 'csv' => Icons.table_chart,
      _ => Icons.insert_drive_file,
    };
  }
}
