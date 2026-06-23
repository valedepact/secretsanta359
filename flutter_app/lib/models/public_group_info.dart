class PublicGroupInfo {
  final String id;
  final String name;
  final double budget;
  final String currency;
  final DateTime eventDate;
  final String? description;
  final String status;

  PublicGroupInfo({
    required this.id,
    required this.name,
    required this.budget,
    required this.currency,
    required this.eventDate,
    required this.status,
    this.description,
  });

  factory PublicGroupInfo.fromJson(Map<String, dynamic> json) {
    return PublicGroupInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      budget: (json['budget'] as num).toDouble(),
      currency: json['currency'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      description: json['description'] as String?,
      status: json['status'] as String,
    );
  }

  bool get isRevealUnlocked => DateTime.now().isAfter(eventDate);
}

class AssignmentReveal {
  final String participantName;
  final String? assignedToName;
  final String groupName;

  AssignmentReveal({
    required this.participantName,
    required this.assignedToName,
    required this.groupName,
  });

  factory AssignmentReveal.fromJson(Map<String, dynamic> json) {
    return AssignmentReveal(
      participantName: json['participant_name'] as String,
      assignedToName: json['assigned_to_name'] as String?,
      groupName: json['group_name'] as String,
    );
  }
}

class GroupRevealEntry {
  final String participantName;
  final String? assignedToName;

  GroupRevealEntry({required this.participantName, this.assignedToName});

  factory GroupRevealEntry.fromJson(Map<String, dynamic> json) {
    return GroupRevealEntry(
      participantName: json['participant_name'] as String,
      assignedToName: json['assigned_to_name'] as String?,
    );
  }
}
