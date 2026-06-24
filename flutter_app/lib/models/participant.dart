enum Gender { male, female, other }

Gender genderFromString(String value) {
  switch (value) {
    case 'male':
      return Gender.male;
    case 'female':
      return Gender.female;
    default:
      return Gender.other;
  }
}

String genderToString(Gender gender) {
  switch (gender) {
    case Gender.male:
      return 'male';
    case Gender.female:
      return 'female';
    case Gender.other:
      return 'other';
  }
}

class Participant {
  final String id;
  final String groupId;
  final String name;
  final Gender gender;
  final String? email;
  final String? wishlist;
  final String? assignedToId;
  final String? assignedToName;
  final String revealCode;
  final DateTime createdAt;

  Participant({
    required this.id,
    required this.groupId,
    required this.name,
    required this.gender,
    required this.revealCode,
    required this.createdAt,
    this.email,
    this.wishlist,
    this.assignedToId,
    this.assignedToName,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      name: json['name'] as String,
      gender: genderFromString(json['gender'] as String? ?? 'other'),
      email: json['email'] as String?,
      wishlist: json['wishlist'] as String?,
      assignedToId: json['assigned_to_id'] as String?,
      assignedToName: json['assigned_to_name'] as String?,
      revealCode: json['reveal_code'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get hasBeenAssigned => assignedToId != null;
}

/// The person a participant is gifting, with their current wishlist.
class Giftee {
  final String name;
  final String? wishlist;

  Giftee({required this.name, this.wishlist});

  factory Giftee.fromJson(Map<String, dynamic> json) {
    return Giftee(
      name: json['name'] as String,
      wishlist: json['wishlist'] as String?,
    );
  }
}
