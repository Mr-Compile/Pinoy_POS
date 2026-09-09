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
import 'package:pinoy_pos/ui/widgets/responsive_create_action.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// Role-aware report screen.
///
/// - `submissionsOnly: true` — Owner inbox ("Submitted Reports"): reports
///   submitted by Staff for review. Requires `view_report_submissions`.
/// - `submissionsOnly: false` — Staff history ("My Reports"): reports
///   authored by the current Staff user. Requires `submit_reports`.
///
/// The Owner is never a report author, so no role combination shows them a
/// "My Reports" view or a submit/import-report authoring action.
class ReportSubmissionsScreen extends ConsumerStatefulWidget {
  /// If true, show only the staff-to-owner submission inbox.
  /// If false, show the current staff user's own report history.
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
      final auth = ref.read(authStateProvider.notifier);
      final canReview = auth.hasPermission('view_report_submissions');
      final canSubmit = auth.hasPermission('submit_reports');

      final reports = widget.submissionsOnly
          ? (canReview ? await reportService.getSubmittedReports() : <ExportHistory>[])
          : (canSubmit ? await reportService.getMyReports() : <ExportHistory>[]);

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
    final auth = ref.read(authStateProvider.notifier);
    final canReview = auth.hasPermission('view_report_submissions');
    final canSubmit = auth.hasPermission('submit_reports');
    final isAuthorized =
        widget.submissionsOnly ? canReview : canSubmit;
    final title =
        widget.submissionsOnly ? 'Submitted Reports' : 'My Reports';

    // Only report authors (Staff) can import an external report file into
    // their own history. The Owner's inbox has no create/import action —
    // they review what Staff submit and manage sales data via Sales.
    final createAction = (!widget.submissionsOnly && canSubmit)
        ? ResponsiveCreateAction(
            label: 'Import Report',
            icon: Icons.file_upload_outlined,
            onPressed: _isLoading ? null : _importReport,
          )
        : null;

    final toolbarAction = createAction?.contentAction(context);
    final createFab = createAction?.fab(context);
    final bottomClearance =
        createAction?.contentBottomClearance(context) ?? 0;

    return Scaffold(
      appBar: AppHeader(
        title: title,
        showBackButton: true,
      ),
      floatingActionButton: createFab,
      body: Column(
        children: [
          if (toolbarAction != null)
            CrudToolbar(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                0,
              ),
              primaryAction: toolbarAction,
            ),
          Expanded(
            child: _buildBody(context, isAuthorized, bottomClearance),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isAuthorized,
    double bottomClearance,
  ) {
    if (!isAuthorized) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'Access restricted',
        message: 'You do not have permission to view this report list.',
      );
    }

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
      final isInboxView = widget.submissionsOnly;
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: isInboxView
            ? 'No submitted reports yet'
            : 'No reports yet',
        message: isInboxView
            ? 'Reports submitted by Staff for your review will appear here.'
            : 'Submit a report from the Reports screen, '
                'or import a report file.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.md + bottomClearance,
        ),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final report = _reports[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _ReportCard(
              report: report,
              staffName: _staffNames[report.createdBy],
              showStaffName: widget.submissionsOnly,
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
    // Only reviewers (Owner) mark a submission as viewed; a report author
    // opening their own history entry does not change its status.
    if (widget.submissionsOnly &&
        ref
            .read(authStateProvider.notifier)
            .hasPermission('view_report_submissions')) {
      final reportService = ref.read(reportServiceProvider);
      await reportService.markReportViewed(report.id!);
    }

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

  /// True in the Owner review inbox, where each card names the Staff member
  /// who submitted the report.
  final bool showStaffName;
  final VoidCallback onTap;

  const _ReportCard({
    required this.report,
    this.staffName,
    required this.showStaffName,
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
        borderRadius: BorderRadius.circular(AppRadius.control),
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
                      showStaffName
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
          borderRadius: BorderRadius.circular(AppRadius.sm),
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
