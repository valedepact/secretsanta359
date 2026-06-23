enum GroupStatus { draft, drawn, completed }

GroupStatus groupStatusFromString(String value) {
  switch (value) {
    case 'drawn':
      return GroupStatus.drawn;
    case 'completed':
      return GroupStatus.completed;
    default:
      return GroupStatus.draft;
  }
}

String groupStatusToString(GroupStatus status) {
  switch (status) {
    case GroupStatus.drawn:
      return 'drawn';
    case GroupStatus.completed:
      return 'completed';
    case GroupStatus.draft:
      return 'draft';
  }
}

class Group {
  final String id;
  final String organizerId;
  final String name;
  final double budget;
  final String currency;
  final DateTime eventDate;
  final String? description;
  final GroupStatus status;
  final String shareCode;
  final DateTime createdAt;

  Group({
    required this.id,
    required this.organizerId,
    required this.name,
    required this.budget,
    required this.currency,
    required this.eventDate,
    required this.shareCode,
    required this.createdAt,
    this.description,
    this.status = GroupStatus.draft,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      name: json['name'] as String,
      budget: (json['budget'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'UGX',
      eventDate: DateTime.parse(json['event_date'] as String),
      description: json['description'] as String?,
      status: groupStatusFromString(json['status'] as String? ?? 'draft'),
      shareCode: json['share_code'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'organizer_id': organizerId,
      'name': name,
      'budget': budget,
      'currency': currency,
      'event_date': eventDate.toIso8601String(),
      'description': description,
      'status': groupStatusToString(status),
      'share_code': shareCode,
    };
  }

  bool get isRevealUnlocked => DateTime.now().isAfter(eventDate) ||
      DateTime.now().isAtSameMomentAs(eventDate);
}
