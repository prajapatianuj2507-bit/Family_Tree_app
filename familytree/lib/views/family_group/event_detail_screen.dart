import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/attachment_helper.dart';
import '../../models/event_model.dart';
import '../../providers/family_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/firebase_service.dart';
import '../components/media_viewer.dart';
import 'add_event_screen.dart';

class EventDetailScreen extends StatelessWidget {
  final EventModel event;

  const EventDetailScreen({Key? key, required this.event}) : super(key: key);

  String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $period';
  }

  void _openGoogleMaps(BuildContext context) async {
    if (event.venue.isEmpty) return;
    final mapUrl = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(event.venue)}';
    try {
      await AttachmentHelper.openInBrowser(mapUrl);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open Google Maps: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _confirmDeleteEvent(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text('Are you sure you want to delete this event? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 12),
                      Text('Deleting event...'),
                    ],
                  ),
                  duration: Duration(seconds: 10),
                ),
              );

              try {
                await FirebaseService.instance.deleteEvent(
                  familyId: event.familyId,
                  eventId: event.eventId,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Event deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete event: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EventModel?>(
      stream: FirebaseService.instance.getEventStream(event.familyId, event.eventId),
      initialData: event,
      builder: (context, snapshot) {
        final currentEvent = snapshot.data ?? event;

        final familyProvider = context.read<FamilyProvider>();
        final creator = familyProvider.findById(currentEvent.createdBy);
        final creatorName = creator != null ? creator.fullName : 'Unknown Member';

        final auth = context.watch<AuthProvider>();
        final currentUser = auth.currentUser;
        final isMaster = auth.isMaster;
        final isAdmin = auth.isAdmin;

        final canManage = !isMaster && (isAdmin || (currentUser != null && currentEvent.createdBy == currentUser.id));

        final images = currentEvent.attachments.where((a) => a.fileType == 'image').toList();
        final videos = currentEvent.attachments.where((a) => a.fileType == 'video').toList();
        final docs = currentEvent.attachments.where((a) => a.fileType != 'image' && a.fileType != 'video').toList();
        final mediaList = currentEvent.attachments.where((a) => a.fileType == 'image' || a.fileType == 'video').toList();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Event Details'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            actions: [
              if (canManage) ...[
                IconButton(
                  tooltip: 'Edit Event',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AddEventScreen(
                          familyId: currentEvent.familyId,
                          eventToEdit: currentEvent,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Delete Event',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDeleteEvent(context),
                ),
              ],
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Event Title & Creator info ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentEvent.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            'Scheduled by $creatorName',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Event Timings ──
                _buildSectionHeader(Icons.access_time, 'Date & Timings'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider, width: 0.8),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow('Starts', _formatDateTime(currentEvent.startDateTime)),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(height: 1, color: AppColors.divider),
                      ),
                      _buildDetailRow('Ends', _formatDateTime(currentEvent.endDateTime)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Venue / Address & Maps link ──
                if (currentEvent.venue.isNotEmpty) ...[
                  _buildSectionHeader(Icons.location_on_outlined, 'Venue & Location'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentEvent.venue,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.map_outlined, color: Colors.white, size: 18),
                            label: const Text(
                              'Open in Google Maps',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _openGoogleMaps(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Event Specific Details ──
                if (currentEvent.details.isNotEmpty) ...[
                  _buildSectionHeader(Icons.info_outline, 'Event Details (Specifics)'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider, width: 0.8),
                    ),
                    child: Text(
                      currentEvent.details,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── General Description ──
                _buildSectionHeader(Icons.description_outlined, 'Description'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider, width: 0.8),
                  ),
                  child: Text(
                    currentEvent.description,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Attachments (with Previews) ──
                if (currentEvent.attachments.isNotEmpty) ...[
                  _buildSectionHeader(Icons.attach_file, 'Media & Document Attachments'),
                  const SizedBox(height: 12),

                  // Image previews (Horizontal gallery thumbnail strip)
                  if (images.isNotEmpty) ...[
                    const Text(
                      'Images (Tap to preview)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final att = images[idx];
                          return GestureDetector(
                            onTap: () {
                              final initialIndex = mediaList.indexOf(att);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EventMediaGalleryScreen(
                                    mediaList: mediaList,
                                    initialIndex: initialIndex >= 0 ? initialIndex : 0,
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 100,
                                height: 100,
                                color: Colors.grey.shade200,
                                child: CachedNetworkImage(
                                  imageUrl: att.fileUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => const Icon(Icons.image_not_supported_outlined),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Video Previews (Cards with play icon overlay)
                  if (videos.isNotEmpty) ...[
                    const Text(
                      'Videos',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: videos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final att = videos[idx];
                        return Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: AppColors.divider, width: 0.8),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.primary,
                              radius: 16,
                              child: Icon(Icons.play_arrow, color: Colors.white, size: 18),
                            ),
                            title: Text(att.fileName, style: const TextStyle(fontWeight: FontWeight.w500)),
                            subtitle: const Text('Tap to play in-app player', style: TextStyle(fontSize: 11)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.textSecondary),
                            onTap: () {
                              final initialIndex = mediaList.indexOf(att);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EventMediaGalleryScreen(
                                    mediaList: mediaList,
                                    initialIndex: initialIndex >= 0 ? initialIndex : 0,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // PDF & Doc files list
                  if (docs.isNotEmpty) ...[
                    const Text(
                      'Documents',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final att = docs[idx];
                        return _DocumentAttachmentTile(attachment: att);
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentAttachmentTile extends StatefulWidget {
  final EventAttachment attachment;

  const _DocumentAttachmentTile({Key? key, required this.attachment}) : super(key: key);

  @override
  State<_DocumentAttachmentTile> createState() => _DocumentAttachmentTileState();
}

class _DocumentAttachmentTileState extends State<_DocumentAttachmentTile> {
  bool _isOpening = false;

  IconData _getIcon() {
    return widget.attachment.fileType == 'pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.insert_drive_file_outlined;
  }

  Future<void> _handleTap(BuildContext context) async {
    setState(() => _isOpening = true);
    try {
      await AttachmentHelper.downloadAndOpen(
        fileUrl: widget.attachment.fileUrl,
        fileName: widget.attachment.fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open document: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (context.mounted) setState(() => _isOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.divider, width: 0.8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(_getIcon(), color: AppColors.primary),
        title: Text(
          widget.attachment.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: const Text('Tap to view document', style: TextStyle(fontSize: 11)),
        trailing: _isOpening
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              )
            : const Icon(Icons.open_in_new, size: 16, color: AppColors.textSecondary),
        onTap: _isOpening ? null : () => _handleTap(context),
      ),
    );
  }
}
