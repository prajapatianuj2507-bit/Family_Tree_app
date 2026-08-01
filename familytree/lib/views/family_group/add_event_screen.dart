import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../app_config.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/firebase_service.dart';
import '../../models/event_model.dart';

class AddEventScreen extends StatefulWidget {
  final String familyId;
  final EventModel? eventToEdit;

  const AddEventScreen({Key? key, required this.familyId, this.eventToEdit}) : super(key: key);

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _detailsController = TextEditingController();
  final _venueController = TextEditingController();

  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();

  DateTime _endDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _endTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 2)));

  final List<File> _selectedFiles = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  List<EventAttachment> _existingAttachments = [];

  @override
  void initState() {
    super.initState();
    if (widget.eventToEdit != null) {
      final e = widget.eventToEdit!;
      _titleController.text = e.title;
      _descController.text = e.description;
      _detailsController.text = e.details;
      _venueController.text = e.venue;
      _startDate = e.startDateTime;
      _startTime = TimeOfDay.fromDateTime(e.startDateTime);
      _endDate = e.endDateTime;
      _endTime = TimeOfDay.fromDateTime(e.endDateTime);
      _existingAttachments = List.from(e.attachments);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _detailsController.dispose();
    _venueController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment(bool isVideo) async {
    try {
      if (isVideo) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: true,
        );
        if (result != null && result.files.isNotEmpty) {
          setState(() {
            for (final f in result.files) {
              if (f.path != null) {
                _selectedFiles.add(File(f.path!));
              }
            }
          });
        }
      } else {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(imageQuality: 85);
        if (pickedFiles.isNotEmpty) {
          setState(() {
            _selectedFiles.addAll(pickedFiles.map((pf) => File(pf.path)));
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick attachment: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFiles.add(File(result.files.single.path!));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick document: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }


  Future<void> _selectDateTime(bool isStart) async {
    final DateTime initial = isStart ? _startDate : (_endDate.isBefore(_startDate) ? _startDate : _endDate);
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: isStart ? DateTime(1800) : _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 50)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null) return;

    if (!mounted) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime == null) return;

    setState(() {
      if (isStart) {
        _startDate = pickedDate;
        _startTime = pickedTime;
        // Automatically sync end date/time to be 2 hours after start
        final combinedStart = DateTime(
          _startDate.year,
          _startDate.month,
          _startDate.day,
          _startTime.hour,
          _startTime.minute,
        );
        final combinedEnd = combinedStart.add(const Duration(hours: 2));
        _endDate = combinedEnd;
        _endTime = TimeOfDay.fromDateTime(combinedEnd);
      } else {
        final combinedStart = DateTime(
          _startDate.year,
          _startDate.month,
          _startDate.day,
          _startTime.hour,
          _startTime.minute,
        );
        final combinedEnd = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        if (combinedEnd.isBefore(combinedStart)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('End Date & Time cannot be before Start Date & Time. Resetting to 2 hours after Start.'),
              backgroundColor: AppColors.error,
            ),
          );
          final adjustedEnd = combinedStart.add(const Duration(hours: 2));
          _endDate = adjustedEnd;
          _endTime = TimeOfDay.fromDateTime(adjustedEnd);
        } else {
          _endDate = pickedDate;
          _endTime = pickedTime;
        }
      }
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final start = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    final end = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End Date & Time cannot be before Start Date & Time.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final currentUser = FirebaseService.instance.currentUser;
      if (widget.eventToEdit != null) {
        final updatedEvent = widget.eventToEdit!.copyWith(
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          details: _detailsController.text.trim(),
          venue: _venueController.text.trim(),
          startDateTime: start,
          endDateTime: end,
          attachments: _existingAttachments,
        );

        await FirebaseService.instance.updateEvent(
          familyId: widget.familyId,
          event: updatedEvent,
          newFiles: _selectedFiles,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Family Event updated successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        final newEvent = EventModel(
          eventId: '',
          familyId: widget.familyId,
          createdBy: currentUser?.uid ?? '',
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          details: _detailsController.text.trim(),
          venue: _venueController.text.trim(),
          startDateTime: start,
          endDateTime: end,
          createdAt: DateTime.now(),
          attachments: [],
          remindersSent: {},
        );

        await FirebaseService.instance.createEvent(
          familyId: widget.familyId,
          event: newEvent,
          files: _selectedFiles,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Family Event created successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save event: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final combinedStart = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    final combinedEnd = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    String formatDt(DateTime dt) {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hr = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hr:$min $period';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.eventToEdit != null ? 'Edit Family Event' : 'Add Family Event'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isSaving
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    widget.eventToEdit != null ? 'Updating event and uploading files...' : 'Saving event and uploading files...',
                    style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Form fields
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Event Title',
                        labelStyle: const TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: AppColors.cardBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _descController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        labelStyle: const TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: AppColors.cardBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a description';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: _detailsController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Details (Specifics)',
                        labelStyle: const TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: AppColors.cardBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Google Places Autocomplete for Venue Selection (with custom stable manual fallback)
                    VenueAutocompleteField(
                      controller: _venueController,
                      labelText: 'Venue / Address',
                    ),
                    const SizedBox(height: 20),

                    // Date Selectors
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDateTime(true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Starts', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatDt(combinedStart),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDateTime(false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Ends', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatDt(combinedEnd),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Attachment Selector Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Event Attachments',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary),
                              tooltip: 'Add Image',
                              onPressed: () => _pickAttachment(false),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_to_queue_outlined, color: AppColors.primary),
                              tooltip: 'Add Video',
                              onPressed: () => _pickAttachment(true),
                            ),
                            IconButton(
                              icon: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primary),
                              tooltip: 'Add PDF / Document',
                              onPressed: _pickDocument,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Existing Attachments Preview
                    if (_existingAttachments.isNotEmpty) ...[
                      const Text(
                        'Current Attachments (Tap X to remove)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _existingAttachments.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final att = _existingAttachments[index];
                            final isImage = att.fileType == 'image';
                            final isVideo = att.fileType == 'video';
                            final isPdf = att.fileType == 'pdf';

                            Widget thumbnailChild;
                            if (isImage) {
                               thumbnailChild = CachedNetworkImage(
                                imageUrl: att.fileUrl,
                                fit: BoxFit.cover,
                                width: 90,
                                height: 90,
                                errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                              );
                            } else if (isVideo) {
                              thumbnailChild = Container(
                                width: 90,
                                height: 90,
                                color: Colors.grey.shade200,
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam, color: AppColors.primary, size: 28),
                                    SizedBox(height: 4),
                                    Text('VIDEO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                                  ],
                                ),
                              );
                            } else {
                              thumbnailChild = Container(
                                width: 90,
                                height: 90,
                                color: Colors.grey.shade200,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                      color: AppColors.primary,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(att.fileType.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                                  ],
                                ),
                              );
                            }

                            return Stack(
                              children: [
                                Container(
                                  width: 90,
                                  height: 90,
                                  margin: const EdgeInsets.only(top: 8, right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.divider, width: 0.8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: thumbnailChild,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _existingAttachments.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: AppColors.error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  left: 4,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    color: Colors.black.withOpacity(0.6),
                                    child: Text(
                                      att.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 8),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_selectedFiles.isEmpty && _existingAttachments.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider, style: BorderStyle.solid),
                        ),
                        child: const Center(
                          child: Text(
                            'No media attachments added.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ),
                      )
                    else if (_selectedFiles.isNotEmpty) ...[
                      const Text(
                        'New Attachments (Tap X to remove)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedFiles.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final file = _selectedFiles[index];
                            final fileName = file.path.split('/').last.split('\\').last;
                            final ext = fileName.split('.').last.toLowerCase();
                            final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
                            final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);

                            Widget thumbnailChild;
                            if (isImage) {
                              thumbnailChild = Image.file(
                                file,
                                fit: BoxFit.cover,
                                width: 90,
                                height: 90,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                              );
                            } else if (isVideo) {
                              thumbnailChild = Container(
                                width: 90,
                                height: 90,
                                color: Colors.grey.shade200,
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam, color: AppColors.primary, size: 28),
                                    SizedBox(height: 4),
                                    Text('VIDEO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                                  ],
                                ),
                              );
                            } else {
                              thumbnailChild = Container(
                                width: 90,
                                height: 90,
                                color: Colors.grey.shade200,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      ext == 'pdf' ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                      color: AppColors.primary,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(ext.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                                  ],
                                ),
                              );
                            }

                            return Stack(
                              children: [
                                Container(
                                  width: 90,
                                  height: 90,
                                  margin: const EdgeInsets.only(top: 8, right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.divider, width: 0.8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: thumbnailChild,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedFiles.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: AppColors.error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  left: 4,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    color: Colors.black.withOpacity(0.6),
                                    child: Text(
                                      fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 8),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 36),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _submitForm,
                        child: Text(
                          widget.eventToEdit != null ? 'Save Changes' : 'Schedule Event',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class VenueAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;

  const VenueAutocompleteField({
    Key? key,
    required this.controller,
    required this.labelText,
  }) : super(key: key);

  @override
  State<VenueAutocompleteField> createState() => _VenueAutocompleteFieldState();
}

class _VenueAutocompleteFieldState extends State<VenueAutocompleteField> {
  List<dynamic> _predictions = [];
  bool _isLoading = false;
  String? _apiError;
  Timer? _debounce;

  void _onChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(value);
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    if (input.isEmpty) {
      setState(() {
        _predictions = [];
        _apiError = null;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&key=${AppConfig.googleApiKey}';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'] as String? ?? '';
        if (status == 'OK') {
          setState(() {
            _predictions = data['predictions'] as List<dynamic>? ?? [];
            _apiError = null;
          });
        } else {
          setState(() {
            _predictions = [];
            _apiError = data['error_message'] ?? 'API error: $status';
          });
          debugPrint('Google Places API Error: ${data['error_message']} (Status: $status)');
        }
      } else {
        setState(() {
          _predictions = [];
          _apiError = 'Network error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _predictions = [];
        _apiError = 'Error fetching suggestions: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.labelText,
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.cardBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                : widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                        onPressed: () {
                          widget.controller.clear();
                          setState(() {
                            _predictions = [];
                            _apiError = null;
                          });
                        },
                      )
                    : const Icon(Icons.location_on_outlined, color: AppColors.primary),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a venue / location';
            }
            return null;
          },
        ),
        if (_apiError != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Places suggestions unavailable: $_apiError\n(You can still type the venue manually below)',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ),
        ],
        if (_predictions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider, width: 0.8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _predictions.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (context, index) {
                final prediction = _predictions[index];
                final description = prediction['description'] as String? ?? '';
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                  title: Text(
                    description,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  ),
                  onTap: () {
                    widget.controller.text = description;
                    widget.controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: description.length),
                    );
                    setState(() {
                      _predictions = [];
                    });
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
