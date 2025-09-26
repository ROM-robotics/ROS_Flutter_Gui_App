import 'dart:convert';

enum NavPointType {
  navGoal,
  chargeStation
}

class NavPoint {
  double x; // Map coordinate
  double y; // Map coordinate
  double theta; // Direction angle (radians)
  String name;
  NavPointType type;

  NavPoint({
    required this.x,
    required this.y,
    required this.theta,
    required this.name,
    required this.type,
  });

  // Create NavPoint from JSON
  factory NavPoint.fromJson(Map<String, dynamic> json) {
    return NavPoint(
      x: json['x'] as double,
      y: json['y'] as double,
      theta: json['theta'] as double,
      name: json['name'] as String,
      type: NavPointType.values[json['type'] as int],
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'theta': theta,
      'name': name,
      'type': type.index,
    };
  }

  // Copy and modify certain properties
  NavPoint copyWith({
    double? x,
    double? y,
    double? theta,
    String? name,
    DateTime? createdAt,
  }) {
    return NavPoint(
      x: x ?? this.x,
      y: y ?? this.y,
      theta: theta ?? this.theta,
      name: name ?? this.name,
      type: type ?? this.type,
    );
  }

  @override
  String toString() {
    return 'NavPoint(x: $x, y: $y, theta: $theta, name: $name, type: $type)';
  }
}
