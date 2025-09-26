import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class PathComponent extends Component with HasGameRef {
  List<vm.Vector2> pointList = [];
  Color color = Colors.green;
  late Timer animationTimer;
  double animationValue = 0.0;
  
  PathComponent({
    required this.pointList, 
    required this.color
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
    add(PathRenderer(
      pointList: pointList,
      color: color,
      animationValue: animationValue,
    ));
  }

  @override
  void update(double dt) {
    animationTimer.update(dt);
    animationValue = (animationTimer.progress * 2.0) % 1.0;
    
    // Update renderer's animation value
    final renderer = children.whereType<PathRenderer>().firstOrNull;
    if (renderer != null) {
      renderer.updateAnimationValue(animationValue);
    }
    
    super.update(dt);
  }

  void updatePath(List<vm.Vector2> newPoints) {
    pointList = newPoints;
    // Update renderer's point list
    final renderer = children.whereType<PathRenderer>().firstOrNull;
    if (renderer != null) {
      renderer.updatePath(newPoints);
    }
  }

  @override
  void onRemove() {
    super.onRemove();
  }
}

class PathRenderer extends Component with HasGameRef {
  List<vm.Vector2> pointList = [];
  Color color;
  double animationValue;

  PathRenderer({
    required this.pointList,
    required this.color,
    required this.animationValue,
  });

  void updatePath(List<vm.Vector2> newPoints) {
    pointList = newPoints;
  }

  void updateAnimationValue(double newValue) {
    animationValue = newValue;
  }

  @override
  void render(Canvas canvas) {
    // Add safety check
    if (!isMounted) {
      return;
    }
    
    try {
      if (pointList.isEmpty || pointList.length < 2) return;

      // Draw main path line
      _drawMainPath(canvas);
      
      // Add flowing arrow texture on the path
      _drawFlowingArrows(canvas);
    } catch (e) {
      print('Error rendering path: $e');
    }
  }

  void _drawMainPath(Canvas canvas) {
    final path = Path();
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Move to first point
    path.moveTo(pointList[0].x, pointList[0].y);
    
    // Connect all points to form path
    for (int i = 1; i < pointList.length; i++) {
      path.lineTo(pointList[i].x, pointList[i].y);
    }

    // Draw main path line
    canvas.drawPath(path, paint);
  }

  void _drawFlowingArrows(Canvas canvas) {
    if (pointList.length < 2) return;

    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.fill;

    // Draw flowing arrows on the path
    for (int i = 0; i < pointList.length - 1; i++) {
      vm.Vector2 currentPoint = pointList[i];
      vm.Vector2 nextPoint = pointList[i + 1];
      
      // Calculate direction of current segment
      vm.Vector2 direction = (nextPoint - currentPoint).normalized();
      
      // Draw flowing arrows
      _drawFlowingArrowSegment(canvas, currentPoint, nextPoint, direction, paint);
    }
  }

  void _drawFlowingArrowSegment(Canvas canvas, vm.Vector2 start, vm.Vector2 end, vm.Vector2 direction, Paint paint) {
    final distance = (end - start).length;
    if (distance == 0) return;
    
    // Arrow parameters
    final arrowSpacing = 12.0;
    final triangleSize = 2.0;
    
    // Animation offset
    double animationOffset = animationValue * arrowSpacing % arrowSpacing;
    
    // Draw flowing triangles
    double currentDistance = animationOffset;
    
    while (currentDistance < distance) {
      if (currentDistance > triangleSize && currentDistance < distance - triangleSize) {
        final triangleCenter = start + direction * currentDistance;
        
        // Calculate triangle opacity
        final distanceRatio = currentDistance / distance;
        final opacity = (0.8 - distanceRatio * 0.3).clamp(0.0, 1.0);
        
        // Draw solid triangle
        final perpendicular = vm.Vector2(-direction.y, direction.x);
        final trianglePoints = [
          triangleCenter + direction * triangleSize, // Front point
          triangleCenter - direction * triangleSize * 0.5 + perpendicular * triangleSize * 0.5, // Left back point
          triangleCenter - direction * triangleSize * 0.5 - perpendicular * triangleSize * 0.5, // Right back point
        ];
        
        final path = Path();
        path.moveTo(trianglePoints[0].x, trianglePoints[0].y);
        path.lineTo(trianglePoints[1].x, trianglePoints[1].y);
        path.lineTo(trianglePoints[2].x, trianglePoints[2].y);
        path.close();
        
        paint.color = color.withOpacity(opacity);
        canvas.drawPath(path, paint);
      }
      
      currentDistance += arrowSpacing;
    }
  }
}
