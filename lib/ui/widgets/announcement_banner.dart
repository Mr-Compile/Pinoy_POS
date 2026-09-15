import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';

/// Dashboard banner for pinned announcements.
///
/// Renders the newest non-expired pinned announcement that the current
/// user has not dismissed, directly under the dashboard greeting. All
/// roles see it: Staff and Admin cannot open the Announcements screen,
/// so this banner (plus their notification) is how they receive
/// announcement content.
///
/// Behaviour:
/// - Tap opens a read-only [AppDialog] with the full announcement; when
///   several announcements are pinned the dialog pages through them.
/// - The close button dismisses the banner for the current user only
///   (persisted via [AnnouncementService.dismissBannerAnnouncement]).
/// - The banner reappears when a different pinned announcement exists or
///   a dismissed one is deleted/recreated under a new id.
class AnnouncementBanner extends ConsumerStatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  ConsumerState<AnnouncementBanner> createState() =>
      _AnnouncementBannerState();
}

class _AnnouncementBannerState extends ConsumerState<AnnouncementBanner> {
  List<Announcement> _visible = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(announcementServiceProvider);
    final pinned = await service.getBannerAnnouncements();
    final dismissed = await service.getDismissedBannerIds();
    if (!mounted) return;
    setState(() {
      _visible =
          pinned.where((a) => !dismissed.contains(a.id)).toList();
      _loaded = true;
    });
  }

  Future<void> _dismiss(Announcement announcement) async {
    final id = announcement.id;
    if (id == null) return;
    await ref
        .read(announcementServiceProvider)
        .dismissBannerAnnouncement(id);
    if (!mounted) return;
    setState(() {
      _visible = _visible.where((a) => a.id != id).toList();
    });
  }

  Future<void> _showDetails() async {
    if (_visible.isEmpty) return;
    var index = 0;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final a = _visible[index];
          final details = [
            'Posted: ${a.createdAt.toLocal().toString().split('.')[0]}',
            'Pinned to top',
            if (a.expiresAt != null)
              'Expires: ${a.expiresAt!.toLocal().toString().split(' ')[0]}',
            if (_visible.length > 1) '${index + 1} of ${_visible.length} pinned',
          ].join('\n');
          return AppDialog(
            type: AppDialogType.info,
            icon: Icons.campaign_outlined,
            title: a.title,
            message: a.content,
            details: details,
            showClose: true,
            actions: [
              if (_visible.length > 1)
                AppDialogAction(
                  label: 'Prev',
                  onPressed: index == 0
                      ? null
                      : (_) => setDialogState(() => index--),
                ),
              if (_visible.length > 1)
                AppDialogAction(
                  label: 'Next',
                  onPressed: index == _visible.length - 1
                      ? null
                      : (_) => setDialogState(() => index++),
                ),
              AppDialogAction(
                label: 'Close',
                isPrimary: true,
                onPressed: (context) =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _visible.isEmpty) return const SizedBox.shrink();

    final brightness = Theme.of(context).brightness;
    final background = AppSemanticColors.resolve(
      AppSemanticColors.infoContainer,
      brightness,
    );
    final accent = AppSemanticColors.resolve(
      AppSemanticColors.info,
      brightness,
    );
    final cs = Theme.of(context).colorScheme;
    final announcement = _visible.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: _showDetails,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.campaign_outlined,
                      size: 16, color: accent),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.push_pin, size: 12, color: accent),
                          const SizedBox(width: Spacing.xs),
                          Flexible(
                            child: Text(
                              announcement.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.titleSmallBold(context)
                                  .copyWith(color: cs.onSurface),
                            ),
                          ),
                          if (_visible.length > 1)
                            Container(
                              margin:
                                  const EdgeInsets.only(left: Spacing.xs),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.16),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                '+${_visible.length - 1} more',
                                style: AppTypography.labelSmall(context)
                                    .copyWith(
                                        color: accent,
                                        fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        announcement.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall(context)
                            .copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                InkWell(
                  onTap: () => _dismiss(announcement),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xs),
                    child: Icon(Icons.close,
                        size: 14, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
