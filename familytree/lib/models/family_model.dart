class FamilyModel {
  final String id;
  final String masterId;
  final String familyName;
  final String description;
  final String? photoUrl;      // NEW
  final int    memberCount;
  final DateTime createdAt;

  const FamilyModel({
    required this.id,
    required this.masterId,
    required this.familyName,
    this.description = '',
    this.photoUrl,
    this.memberCount = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id':          id,
    'masterId':    masterId,
    'familyName':  familyName,
    'description': description,
    'photoUrl':    photoUrl,
    'memberCount': memberCount,
    'createdAt':   createdAt.toIso8601String(),
  };

  factory FamilyModel.fromMap(Map<String, dynamic> map) => FamilyModel(
    id:          map['id']          as String? ?? '',
    masterId:    map['masterId']    as String? ?? '',
    familyName:  map['familyName']  as String? ?? '',
    description: map['description'] as String? ?? '',
    photoUrl:    map['photoUrl']    as String?,
    memberCount: map['memberCount'] as int?    ?? 0,
    createdAt:   DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  FamilyModel copyWith({
    String? id, String? masterId, String? familyName,
    String? description, String? photoUrl, int? memberCount, DateTime? createdAt,
  }) => FamilyModel(
    id:          id          ?? this.id,
    masterId:    masterId    ?? this.masterId,
    familyName:  familyName  ?? this.familyName,
    description: description ?? this.description,
    photoUrl:    photoUrl    ?? this.photoUrl,
    memberCount: memberCount ?? this.memberCount,
    createdAt:   createdAt   ?? this.createdAt,
  );
}
