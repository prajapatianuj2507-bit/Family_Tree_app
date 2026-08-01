import 'package:cloud_firestore/cloud_firestore.dart';

class EventAttachment {
  final String fileUrl;
  final String fileType; // 'image' | 'video' | 'pdf' | 'doc'
  final String fileName;

  const EventAttachment({
    required this.fileUrl,
    required this.fileType,
    required this.fileName,
  });

  Map<String, dynamic> toMap() => {
    'fileUrl': fileUrl,
    'fileType': fileType,
    'fileName': fileName,
  };

  factory EventAttachment.fromMap(Map<String, dynamic> map) => EventAttachment(
    fileUrl: map['fileUrl'] as String? ?? '',
    fileType: map['fileType'] as String? ?? '',
    fileName: map['fileName'] as String? ?? '',
  );
}

class EventModel {
  final String eventId;
  final String familyId;
  final String createdBy;
  final String title;
  final String description;
  final String details;
  final String venue;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final DateTime createdAt;
  final List<EventAttachment> attachments;
  final Map<String, bool> remindersSent;

  const EventModel({
    required this.eventId,
    required this.familyId,
    required this.createdBy,
    required this.title,
    required this.description,
    this.details = '',
    this.venue = '',
    required this.startDateTime,
    required this.endDateTime,
    required this.createdAt,
    this.attachments = const [],
    this.remindersSent = const {},
  });

  Map<String, dynamic> toMap() => {
    'eventId': eventId,
    'familyId': familyId,
    'createdBy': createdBy,
    'title': title,
    'description': description,
    'details': details,
    'venue': venue,
    'startDateTime': Timestamp.fromDate(startDateTime),
    'endDateTime': Timestamp.fromDate(endDateTime),
    'createdAt': Timestamp.fromDate(createdAt),
    'attachments': attachments.map((a) => a.toMap()).toList(),
    'remindersSent': remindersSent,
  };

  factory EventModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseDateTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    final list = map['attachments'] as List<dynamic>? ?? [];
    final parsedAttachments = list
        .map((item) => EventAttachment.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList();

    return EventModel(
      eventId: docId ?? map['eventId'] as String? ?? '',
      familyId: map['familyId'] as String? ?? '',
      createdBy: map['createdBy'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      details: map['details'] as String? ?? '',
      venue: map['venue'] as String? ?? '',
      startDateTime: parseDateTime(map['startDateTime']),
      endDateTime: parseDateTime(map['endDateTime']),
      createdAt: parseDateTime(map['createdAt'] ?? map['startDateTime']),
      attachments: parsedAttachments,
      remindersSent: Map<String, bool>.from(map['remindersSent'] as Map? ?? {}),
    );
  }

  EventModel copyWith({
    String? eventId,
    String? familyId,
    String? createdBy,
    String? title,
    String? description,
    String? details,
    String? venue,
    DateTime? startDateTime,
    DateTime? endDateTime,
    DateTime? createdAt,
    List<EventAttachment>? attachments,
    Map<String, bool>? remindersSent,
  }) => EventModel(
    eventId: eventId ?? this.eventId,
    familyId: familyId ?? this.familyId,
    createdBy: createdBy ?? this.createdBy,
    title: title ?? this.title,
    description: description ?? this.description,
    details: details ?? this.details,
    venue: venue ?? this.venue,
    startDateTime: startDateTime ?? this.startDateTime,
    endDateTime: endDateTime ?? this.endDateTime,
    createdAt: createdAt ?? this.createdAt,
    attachments: attachments ?? this.attachments,
    remindersSent: remindersSent ?? this.remindersSent,
  );
}
