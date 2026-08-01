enum Designation { business, job, other }
enum Gender { male, female, other }

class MemberModel {
  final String id;
  final String familyId;        // ← NEW: isolates each family
  final String firstName;
  final String middleName;
  final String lastName;
  final String mobileNumber;
  final String password;
  final Gender gender;
  final String education;
  final String nativePlace;
  final String currentAddress;
  final Designation designation;
  final String? profileImageUrl;
  final String? fatherId;
  final String? motherId;
  final String? spouseId;
  final String role;

  const MemberModel({
    required this.id,
    required this.familyId,
    required this.firstName,
    this.middleName = '',
    required this.lastName,
    required this.mobileNumber,
    required this.password,
    required this.gender,
    this.education = '',
    this.nativePlace = '',
    this.currentAddress = '',
    required this.designation,
    this.profileImageUrl,
    this.fatherId,
    this.motherId,
    this.spouseId,
    this.role = 'member',
  });

  String get fullName {
    final parts = [firstName, middleName, lastName]
        .where((p) => p.trim().isNotEmpty)
        .toList();
    return parts.join(' ');
  }

  String get designationLabel {
    switch (designation) {
      case Designation.business: return 'Business';
      case Designation.job:      return 'Job';
      case Designation.other:    return 'Other';
    }
  }

  Map<String, dynamic> toMap() => {
    'id':             id,
    'familyId':       familyId,
    'firstName':      firstName,
    'middleName':     middleName,
    'lastName':       lastName,
    'mobileNumber':   mobileNumber,
    'password':       password,
    'gender':         gender.name,
    'education':      education,
    'nativePlace':    nativePlace,
    'currentAddress': currentAddress,
    'designation':    designation.name,
    'profileImageUrl':profileImageUrl,
    'fatherId':       fatherId,
    'motherId':       motherId,
    'spouseId':       spouseId,
    'role':           role,
  };

  factory MemberModel.fromMap(Map<String, dynamic> map) => MemberModel(
    id:             map['id']             as String? ?? '',
    familyId:       map['familyId']       as String? ?? '',
    firstName:      map['firstName']      as String? ?? '',
    middleName:     map['middleName']      as String? ?? '',
    lastName:       map['lastName']       as String? ?? '',
    mobileNumber:   map['mobileNumber']   as String? ?? '',
    password:       map['password']       as String? ?? '',
    gender:         Gender.values.firstWhere(
            (g) => g.name == (map['gender'] as String? ?? 'other'),
        orElse: () => Gender.other),
    education:      map['education']      as String? ?? '',
    nativePlace:    map['nativePlace']    as String? ?? '',
    currentAddress: map['currentAddress'] as String? ?? '',
    designation:    Designation.values.firstWhere(
            (d) => d.name == (map['designation'] as String? ?? 'other'),
        orElse: () => Designation.other),
    profileImageUrl: map['profileImageUrl'] as String?,
    fatherId:        map['fatherId']        as String?,
    motherId:        map['motherId']        as String?,
    spouseId:        map['spouseId']        as String?,
    role:            map['role']            as String? ?? 'member',
  );

  MemberModel copyWith({
    String? id,
    String? familyId,
    String? firstName,
    String? middleName,
    String? lastName,
    String? mobileNumber,
    String? password,
    Gender? gender,
    String? education,
    String? nativePlace,
    String? currentAddress,
    Designation? designation,
    String? profileImageUrl,
    String? fatherId,
    String? motherId,
    String? spouseId,
    String? role,
  }) => MemberModel(
    id:             id             ?? this.id,
    familyId:       familyId       ?? this.familyId,
    firstName:      firstName      ?? this.firstName,
    middleName:     middleName     ?? this.middleName,
    lastName:       lastName       ?? this.lastName,
    mobileNumber:   mobileNumber   ?? this.mobileNumber,
    password:       password       ?? this.password,
    gender:         gender         ?? this.gender,
    education:      education      ?? this.education,
    nativePlace:    nativePlace    ?? this.nativePlace,
    currentAddress: currentAddress ?? this.currentAddress,
    designation:    designation    ?? this.designation,
    profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    fatherId:       fatherId       ?? this.fatherId,
    motherId:       motherId       ?? this.motherId,
    spouseId:       spouseId       ?? this.spouseId,
    role:           role           ?? this.role,
  );
}