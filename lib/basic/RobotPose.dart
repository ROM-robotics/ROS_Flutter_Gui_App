import 'dart:math';
import 'package:vector_math/vector_math_64.dart';

class RobotPose {
  double x;
  double y;
  double theta;

  RobotPose(this.x, this.y, this.theta);

  RobotPose.zero()
      : x = 0,
        y = 0,
        theta = 0;

  // Parse from JSON
  // Constructor
  RobotPose.fromJson(Map<String, dynamic> json)
      : x = json['x'],
        y = json['y'],
        theta = json['theta'];

  // Methods
  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'theta': theta,
      };
  @override
  String toString() => 'RobotPose(x: $x, y: $y, theta: $theta)';
  RobotPose operator +(RobotPose other) =>
      RobotPose(x + other.x, y + other.y, theta + other.theta);
  RobotPose operator -(RobotPose other) =>
      RobotPose(x - other.x, y - other.y, theta - other.theta);
}

/*
@desc Sum of two poses where p2 represents increment. This function adds a P2 increment to the P1 pose
*/
RobotPose absoluteSum(RobotPose p1, RobotPose p2) {
  double s = sin(p1.theta);
  double c = cos(p1.theta);
  return RobotPose(c * p2.x - s * p2.y, s * p2.x + c * p2.y, p2.theta) + p1;
}

/*
@desc Difference between two poses, calculates P1's coordinates in the coordinate system with P2 as origin.
*/
RobotPose absoluteDifference(RobotPose p1, RobotPose p2) {
  RobotPose delta = p1 - p2;
  delta.theta = atan2(sin(delta.theta), cos(delta.theta));
  double s = sin(p2.theta), c = cos(p2.theta);
  return RobotPose(
      c * delta.x + s * delta.y, -s * delta.x + c * delta.y, delta.theta);
}

double deg2rad(double deg) => deg * pi / 180;

double rad2deg(double rad) => rad * 180 / pi;

RobotPose GetRobotPoseFromMatrix(Matrix4 matrix) {
  // Extract translation (x, y)
  double x = matrix.storage[12];
  double y = matrix.storage[13];
  // Extract rotation angle theta (radians)
  double theta = atan2(matrix.storage[1], matrix.storage[0]); // Calculate theta

  return RobotPose(x, y, theta);
}
