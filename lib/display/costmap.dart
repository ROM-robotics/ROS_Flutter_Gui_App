import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:ros_flutter_gui_app/basic/occupancy_map.dart';

class CostMapComponent extends Component {
  final double opacity;
  final bool isGlobal;
  
  ui.Image? _cachedImage;
  OccupancyMap? _lastProcessedMap;
  double _lastOpacity = 0.3;
  bool _isProcessing = false;

  CostMapComponent({
    this.opacity = 0.2,
    this.isGlobal = false,
  }) {
    _lastOpacity = opacity;
  }

  bool get hasLayout => true;

  @override
  void onRemove() {
    _cachedImage?.dispose();
    _cachedImage = null; // Set to null to prevent subsequent drawing
    _lastProcessedMap = null;
    super.onRemove();
  }

  Future<void> updateCostMap(OccupancyMap costMap) async {
    // Check if reprocessing is needed
    if (_lastProcessedMap == costMap && _lastOpacity == opacity && _cachedImage != null) {
      return;
    }

    if (_isProcessing) return;
    _isProcessing = true;

    try {
      if (costMap.data.isEmpty || costMap.mapConfig.width == 0 || costMap.mapConfig.height == 0) {
        _cachedImage?.dispose();
        _cachedImage = null;
        _lastProcessedMap = costMap;
        _lastOpacity = opacity;
        return;
      }

      final int width = costMap.mapConfig.width;
      final int height = costMap.mapConfig.height;

      List<int> costMapColors = costMap.getCostMapData();
      
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        Uint8List.fromList(costMapColors),
      );
      
      final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;
      
      buffer.dispose();
      descriptor.dispose();
      codec.dispose();
      
      _cachedImage?.dispose();
      _cachedImage = image;
      _lastProcessedMap = costMap;
      _lastOpacity = opacity;
      
    } catch (e) {
      print('Error processing costmap: $e');
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void render(Canvas canvas) {
    // Add additional safety checks
    if (_cachedImage == null || !isMounted) {
      return;
    }

    try {
      final Paint paint = Paint()
        ..colorFilter = ColorFilter.mode(
          Colors.white.withOpacity(opacity),
          BlendMode.modulate,
        );
      
      canvas.drawImage(_cachedImage!, Offset.zero, paint);
    } catch (e) {
      print('Error rendering costmap: $e');
      // If drawing fails, clean up cached image
      _cachedImage?.dispose();
      _cachedImage = null;
    }
  }
}
