import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/firebase_service.dart';
import '../../providers/family_group_provider.dart';
import '../../providers/auth_provider.dart';
import '../family_group/event_detail_screen.dart';

class MasterNotificationsScreen extends StatelessWidget {
  const MasterNotificationsScreen({super.key});

  DateTime _parseTimestamp(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final familyIds = context
        .watch<FamilyGroupProvider>()
        .families
        .map((f) => f.id)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: familyIds.isEmpty
          ? const Center(
              child: Text(
                'No families yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirebaseService.instance.resetRequestsStream(familyIds),
              builder: (context, resetSnap) {
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: FirebaseService.instance.masterNotificationsStream(),
                  builder: (context, notifSnap) {
                    if (resetSnap.connectionState == ConnectionState.waiting &&
                        notifSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final resets = resetSnap.data ?? [];
                    final notifs = notifSnap.data ?? [];

                    final currentUser = context.read<AuthProvider>().currentUser;
                    if (currentUser != null && notifs.isNotEmpty) {
                      final unreadIds = notifs
                          .where((n) {
                            final readBy = n['readBy'] as List<dynamic>? ?? [];
                            return !readBy.contains(currentUser.id);
                          })
                          .map((n) => n['id'] as String)
                          .toList();
                      if (unreadIds.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          FirebaseService.instance.markNotificationsAsRead(currentUser.id, unreadIds);
                        });
                      }
                    }

                    final List<Map<String, dynamic>> combined = [];

                    combined.addAll(resets.map((r) => {
                          ...r,
                          'uiType': 'password_reset',
                          'timestamp': _parseTimestamp(r['requestedAt']),
                        }));

                    combined.addAll(notifs.map((n) => {
                          ...n,
                          'uiType': 'event_notification',
                          'timestamp': _parseTimestamp(n['createdAt']),
                        }));

                    // Sort combined list by timestamp descending
                    combined.sort((a, b) {
                      final aTime = a['timestamp'] as DateTime;
                      final bTime = b['timestamp'] as DateTime;
                      return bTime.compareTo(aTime);
                    });

                    if (combined.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_none_outlined,
                              size: 72,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No notifications',
                              style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Pending resets and event notifications will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: combined.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final item = combined[i];
                        if (item['uiType'] == 'password_reset') {
                          return _MasterResetRequestCard(request: item);
                        } else {
                          return _MasterEventNotificationCard(notification: item);
                        }
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Password Reset Request Card (copied from reset_requests_screen.dart)
// ─────────────────────────────────────────────────────────────
class _MasterResetRequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  const _MasterResetRequestCard({required this.request});

  @override
  State<_MasterResetRequestCard> createState() => _MasterResetRequestCardState();
}

class _MasterResetRequestCardState extends State<_MasterResetRequestCard> {
  bool _loading = false;

  Future<void> _approve() async {
    final requestId = widget.request['id'] as String;
    final memberId = widget.request['memberId'] as String;
    final memberName = widget.request['memberName'] as String? ?? '';
    final mobile = widget.request['mobileNumber'] as String? ?? '';
    final rootNav = Navigator.of(context, rootNavigator: true);

    setState(() => _loading = true);
    try {
      final password = await FirebaseService.instance
          .approvePasswordReset(requestId, memberId);

      _showApprovedDialog(
        navigator: rootNav,
        name: memberName,
        mobile: mobile,
        password: password,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Request'),
        content: Text(
            'Reject the password reset request from '
            '${widget.request['memberName']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await FirebaseService.instance
          .rejectPasswordReset(widget.request['id'] as String);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request rejected'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static void _showApprovedDialog({
    required NavigatorState navigator,
    required String name,
    required String mobile,
    required String password,
  }) {
    showDialog(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: AppColors.success),
          SizedBox(width: 8),
          Text('Password Reset Done'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name\'s password has been reset.',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            const Text('Share these login credentials:',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            _credRow(navigator.context, Icons.phone, 'Mobile', mobile),
            const SizedBox(height: 8),
            _credRow(navigator.context, Icons.lock, 'Password', password),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Share this new password with the member. It cannot be shown again.',
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'Mobile: $mobile\nPassword: $password'));
              ScaffoldMessenger.of(navigator.context).showSnackBar(
                  const SnackBar(content: Text('Credentials copied')));
            },
            child: const Text('Copy All'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => navigator.pop(),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  static Widget _credRow(
      BuildContext ctx, IconData icon, String label, String value) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('$label copied')));
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          const Icon(Icons.copy, size: 14, color: AppColors.textSecondary),
        ]),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.request['memberName'] as String? ?? '';
    final mobile = widget.request['mobileNumber'] as String? ?? '';
    final familyId = widget.request['familyId'] as String? ?? '';
    final timestamp = widget.request['timestamp'] as DateTime;

    final families = context.watch<FamilyGroupProvider>().families;
    final familyName = families
            .where((f) => f.id == familyId)
            .map((f) => f.familyName)
            .toList()
            .firstOrNull ??
        'Unknown Family';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.orange.shade50,
                child: const Icon(Icons.lock_reset, color: Colors.orange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(mobile, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.family_restroom, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(familyName,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
                    ]),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_timeAgo(timestamp),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
            const SizedBox(height: 10),
            const Text(
                'This member has forgotten their password and is requesting a reset.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _reject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _approve,
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Master Event Notification Card (Global Event created/reminded)
// ─────────────────────────────────────────────────────────────
class _MasterEventNotificationCard extends StatelessWidget {
  final Map<String, dynamic> notification;
  const _MasterEventNotificationCard({required this.notification});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _handleNotificationTap(BuildContext context) async {
    final eventId = notification['eventId'] as String? ?? '';
    final familyId = notification['familyId'] as String? ?? '';
    if (eventId.isEmpty || familyId.isEmpty) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final event = await FirebaseService.instance.getEvent(familyId, eventId);
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        if (event != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EventDetailScreen(event: event),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This event has been deleted or is no longer available.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading event: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = notification['title'] as String? ?? 'Family Event Alert';
    final body = notification['body'] as String? ?? '';
    final familyName = notification['familyName'] as String? ?? 'Unknown Family';
    final timestamp = notification['timestamp'] as DateTime;
    final isReminder = notification['type'] == 'event_reminder';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider, width: 0.8),
      ),
      child: InkWell(
        onTap: () => _handleNotificationTap(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isReminder ? Colors.indigo.shade50 : AppColors.primary.withOpacity(0.08),
                child: Icon(
                  isReminder ? Icons.alarm : Icons.campaign_outlined,
                  color: isReminder ? Colors.indigo : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                        Text(
                          _timeAgo(timestamp),
                          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.family_restroom, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          familyName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Text(
                          'Tap to view event details',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.arrow_forward, size: 10, color: AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
