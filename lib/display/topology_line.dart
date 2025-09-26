import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:ros_flutter_gui_app/basic/topology_map.dart';
import 'package:ros_flutter_gui_app/basic/nav_point.dart';
import 'package:ros_flutter_gui_app/basic/occupancy_map.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class TopologyLine extends Component with HasGameRef {
  final List<NavPoint> points;
  final List<TopologyRoute> routes;
  final OccupancyMap? occMap;
  final RosChannel? rosChannel;
  late Timer animationTimer;
  double animationValue = 0.0;

  TopologyLine({
    required this.points,
    required this.routes,
    this.occMap,
    this.rosChannel,
  });

  @override
  Future<void> onLoad() async {
    animationTimer = Timer(
      2.0,
      onTick: () {
        animationValue = 0.0;
      },
      repeat: true,
    );
    add(TopologyLineRenderer(
      points: points,
      routes: routes,
      occMap: occMap,
      rosChannel: rosChannel,
      animationValue: animationValue,
    ));
  }

  @override
  void update(double dt) {
    animationTimer.update(dt);
    animationValue = (animationTimer.progress * 2.0) % 1.0;
    super.update(dt);
  }

  @override
  void onRemove() {
    super.onRemove();
  }
}

class TopologyLineRenderer extends Component with HasGameRef {
  final List<NavPoint> points;
  final List<TopologyRoute> routes;
  final OccupancyMap? occMap;
  final RosChannel? rosChannel;
  final double animationValue;

  TopologyLineRenderer({
    required this.points,
    required this.routes,
    this.occMap,
    this.rosChannel,
    required this.animationValue,
  });

  // Get current map data
  OccupancyMap? get currentMap {
    if (occMap != null) {
      return occMap;
    }
    if (rosChannel != null) {
      return rosChannel!.map_.value;
    }
    return null;
  }

  // Get map resolution
  double get mapResolution => currentMap?.mapConfig.resolution ?? 0.05;

  // Get map origin
  Offset get mapOrigin => currentMap != null 
      ? Offset(currentMap!.mapConfig.originX, currentMap!.mapConfig.originY)
      : Offset.zero;

  @override
  void render(Canvas canvas) {
    // Add safety check
    if (!isMounted) {
      return;
    }
    
    try {
      final paint = Paint()
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;

      final currentMapData = currentMap;
      if (currentMapData == null) {
        return; // Don't render when there's no map data
      }

      final Map<String, Offset> pointMap = {};
      for (final point in points) {
        var occPose = currentMapData.xy2idx(vm.Vector2(point.x, point.y));
        pointMap[point.name] = Offset(occPose.x, occPose.y);
      }

      // Count connections for each path to determine if bidirectional
      final Map<String, List<TopologyRoute>> connectionMap = {};
      for (final route in routes) {
        final key = _getConnectionKey(route.fromPoint, route.toPoint);
        connectionMap.putIfAbsent(key, () => []).add(route);
      }

      // Draw paths
      for (final entry in connectionMap.entries) {
        final routeList = entry.value;
        final firstRoute = routeList.first;
        
        final fromPoint = pointMap[firstRoute.fromPoint];
        final toPoint = pointMap[firstRoute.toPoint];
        
        if (fromPoint != null && toPoint != null) {
          final isBidirectional = routeList.length > 1;
          
          if (isBidirectional) {
            _drawBidirectionalPath(canvas, fromPoint, toPoint, paint);
          } else {
            _drawUnidirectionalPath(canvas, fromPoint, toPoint, paint);
          }
        }
      }
    } catch (e) {
      print('Error rendering topology line: $e');
    }
  }

  String _getConnectionKey(String from, String to) {
    final sorted = [from, to]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Map<String, Offset> _adjustLineToPointEdges(Offset from, Offset to) {
    const double pointRadius = 2.0; // Shorten distance at both ends of points
    
    final direction = to - from;
    final distance = direction.distance;
    
    if (distance == 0) {
      return {'from': from, 'to': to};
    }
    
    final normalizedDirection = direction / distance;
    
    // Adjust start and end points so line segments start from point edges
    final adjustedFrom = from + normalizedDirection * pointRadius;
    final adjustedTo = to - normalizedDirection * pointRadius;
    
    return {'from': adjustedFrom, 'to': adjustedTo};
  }

  void _drawUnidirectionalPath(Canvas canvas, Offset from, Offset to, Paint paint) {
    // Shorten line segment to point edge
    final adjustedPoints = _adjustLineToPointEdges(from, to);
    final adjustedFrom = adjustedPoints['from']!;
    final adjustedTo = adjustedPoints['to']!;
    
    // Draw base path
    paint.color = Color(0xFF6B7280).withOpacity(0.4); // Modern gray
    paint.strokeWidth = 1.0;
    canvas.drawLine(adjustedFrom, adjustedTo, paint);
    
    // Draw arrow flow effect
    _drawArrowFlow(canvas, adjustedFrom, adjustedTo, paint, Color(0xFF3B82F6), 0); // Modern blue
  }

  void _drawBidirectionalPath(Canvas canvas, Offset from, Offset to, Paint paint) {
    // Shorten line segment to point edge
    final adjustedPoints = _adjustLineToPointEdges(from, to);
    final adjustedFrom = adjustedPoints['from']!;
    final adjustedTo = adjustedPoints['to']!;
    
    final direction = (adjustedTo - adjustedFrom).normalize();
    final perpendicular = Offset(-direction.dy, direction.dx);
    final offset = perpendicular;

    final line1Start = adjustedFrom + offset;
    final line1End = adjustedTo + offset;
    final line2Start = adjustedFrom - offset;
    final line2End = adjustedTo - offset;

    // Draw base path
    paint.color = Color(0xFF6B7280).withOpacity(0.4); // Modern gray
    paint.strokeWidth = 1.0;
    canvas.drawLine(line1Start, line1End, paint);
    canvas.drawLine(line2Start, line2End, paint);

    // Draw arrow flow effect
    _drawArrowFlow(canvas, line1Start, line1End, paint, Color(0xFF10B981), 0); // Modern green
    _drawArrowFlow(canvas, line2End, line2Start, paint, Color(0xFF10B981), 0.5);
  }

  void _drawArrowFlow(Canvas canvas, Offset start, Offset end, Paint paint, Color color, double phaseOffset) {
    final direction = end - start;
    final distance = direction.distance;
    if (distance == 0) return;
    
    final normalizedDirection = direction / distance;
    final perpendicular = Offset(-normalizedDirection.dy, normalizedDirection.dx);
    
    // Arrow parameters
    final arrowSpacing = 10.0;
    final triangleSize = 1.0; // Triangle size, ensure within path
    
    // Animation offset (correct direction)
    double animationOffset = animationValue * arrowSpacing % arrowSpacing;
    
    // Draw flowing triangles
    double currentDistance = animationOffset;
    
    while (currentDistance < distance) {
      if (currentDistance > triangleSize && currentDistance < distance - triangleSize) {
        final triangleCenter = start + normalizedDirection * currentDistance;
        
        // Calculate triangle opacity
        final distanceRatio = currentDistance / distance;
        final opacity = (0.8 - distanceRatio * 0.3).clamp(0.0, 1.0);
        
        // Draw solid triangle
        final trianglePoints = [
          triangleCenter + normalizedDirection * triangleSize, // Front point
          triangleCenter - normalizedDirection * triangleSize * 0.5 + perpendicular * triangleSize * 0.5, // Left rear point
          triangleCenter - normalizedDirection * triangleSize * 0.5 - perpendicular * triangleSize * 0.5, // Right rear point
        ];
        
        final path = Path();
        path.moveTo(trianglePoints[0].dx, trianglePoints[0].dy);
        path.lineTo(trianglePoints[1].dx, trianglePoints[1].dy);
        path.lineTo(trianglePoints[2].dx, trianglePoints[2].dy);
        path.close();
        
        paint.color = color.withOpacity(opacity);
        paint.style = PaintingStyle.fill;
        canvas.drawPath(path, paint);
      }
      
      currentDistance += arrowSpacing;
    }
  }
}

extension OffsetExtension on Offset {
  Offset normalize() {
    final length = distance;
    if (length == 0) return Offset.zero;
    return this / length;
  }
}
