import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:ros_flutter_gui_app/page/main_flame.dart';
import 'package:ros_flutter_gui_app/provider/global_state.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:ros_flutter_gui_app/basic/action_status.dart';
import 'package:ros_flutter_gui_app/basic/RobotPose.dart';
import 'package:ros_flutter_gui_app/page/map_edit_page.dart';
import 'package:ros_flutter_gui_app/provider/nav_point_manager.dart';
import 'package:ros_flutter_gui_app/provider/them_provider.dart';
import 'package:ros_flutter_gui_app/basic/nav_point.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:ros_flutter_gui_app/global/setting.dart';
import 'package:ros_flutter_gui_app/page/gamepad_widget.dart';
import 'package:ros_flutter_gui_app/basic/diagnostic_status.dart';
import 'package:ros_flutter_gui_app/page/diagnostic_page.dart';
import 'package:ros_flutter_gui_app/provider/diagnostic_manager.dart';



class MainFlamePage extends StatefulWidget {
  @override
  _MainFlamePageState createState() => _MainFlamePageState();
}

class _MainFlamePageState extends State<MainFlamePage> {
  late MainFlame game;
  bool showLayerControl = false;
  bool showCamera = false;
  NavPoint? selectedNavPoint;
  
  // Camera-related variables
  Offset camPosition = Offset(30, 10); // Initial position
  bool isCamFullscreen = false; // Whether fullscreen
  Offset camPreviousPosition = Offset(30, 10); // Save position before entering fullscreen
  late double camWidgetWidth;
  late double camWidgetHeight;

  @override
  void initState() {
    super.initState();
    final rosChannel = Provider.of<RosChannel>(context, listen: false);
    final globalState = Provider.of<GlobalState>(context, listen: false);
    final navPointManager = Provider.of<NavPointManager>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    game = MainFlame(
      rosChannel: rosChannel, 
      themeProvider: themeProvider,
      globalState: globalState,
      navPointManager: navPointManager,
    );
    game.onNavPointTap = (NavPoint? point) {
      setState(() {
        selectedNavPoint = point;
      });
    };
    
    // Load layer settings
    Provider.of<GlobalState>(context, listen: false).loadLayerSettings();
    
    // Initialize camera dimensions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final screenSize = MediaQuery.of(context).size;
        camWidgetWidth = screenSize.width / 3.5;
        camWidgetHeight = camWidgetWidth / (globalSetting.imageWidth / globalSetting.imageHeight);
      }
    });
    
    // Listen for diagnostic data
    _setupDiagnosticListener();
  }
  
  // Reload navigation points and map data
  Future<void> _reloadData() async {
    await game.reloadNavPointsAndMap();
  }

  // Set up diagnostic data listener
  void _setupDiagnosticListener() {
    final rosChannel = Provider.of<RosChannel>(context, listen: false);
    
    // Set up new error/warning callback
    rosChannel.diagnosticManager.setOnNewErrorsWarnings(_onNewErrorsWarnings);
  }


  // New error/warning/stale callback
  void _onNewErrorsWarnings(List<Map<String, dynamic>> newErrorsWarnings) {
    for (var errorWarning in newErrorsWarnings) {
      final hardwareId = errorWarning['hardwareId'] as String;
      final componentName = errorWarning['componentName'] as String;
      final state = errorWarning['state'] as DiagnosticState;
      
      // Only show toast for error, warning and stale states
      if (state.level == DiagnosticStatus.ERROR || 
          state.level == DiagnosticStatus.WARN || 
          state.level == DiagnosticStatus.STALE) {
        _showDiagnosticToast(hardwareId, componentName, state);
      }
    }
  }

  // Show diagnostic toast notification
  void _showDiagnosticToast(String hardwareId, String componentName, DiagnosticState state) {
    if (!mounted) return;
    
    String levelText;
    Color levelColor;
    ToastificationType toastType;
    IconData iconData;
    
    switch (state.level) {
      case DiagnosticStatus.WARN:
        levelText = 'Warning';
        levelColor = Colors.orange;
        toastType = ToastificationType.warning;
        iconData = Icons.warning;
        break;
      case DiagnosticStatus.ERROR:
        levelText = 'Error';
        levelColor = Colors.red;
        toastType = ToastificationType.error;
        iconData = Icons.error;
        break;
      case DiagnosticStatus.STALE:
        levelText = 'Stale';
        levelColor = Colors.grey;
        toastType = ToastificationType.info;
        iconData = Icons.schedule;
        break;
      default:
        return; // Other statuses don't show toast
    }
    
    toastification.show(
      context: context,
      type: toastType,
      title: Text('Health Diagnostic: [$levelText] $componentName'),
      description: Text('Hardware ID: $hardwareId\nMessage: ${state.message}'),
      autoCloseDuration: const Duration(seconds: 5),
      icon: Icon(
        iconData,
        color: levelColor,
      ),
    );
  }

    @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
          body: Stack(
            children: [
              // Game canvas
              Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent) {
                    final position = Vector2(pointerSignal.position.dx, pointerSignal.position.dy);
                    game.onScroll(pointerSignal.scrollDelta.dy, position);
                  }
                },
                child: GestureDetector(
                  onScaleStart: (details) {
                    final position = Vector2(details.localFocalPoint.dx, details.localFocalPoint.dy);
                    game.onScaleStart(position);
                  },
                  onScaleUpdate: (details) {
                    final position = Vector2(details.localFocalPoint.dx, details.localFocalPoint.dy);
                    game.onScaleUpdate(details.scale, position);
                  },
                  onScaleEnd: (details) {
                    game.onScaleEnd();
                  },
                  onTapDown: (details) {
                    // Handle click events, detect waypoints
                    game.onTap(details.localPosition);
                  },
                  child: GameWidget(game: game),
                ),
              ),
              _buildTopMenuBar(context, theme),
              _buildLeftToolbar(context, theme),
              _buildRightToolbar(context, theme),
              _buildBottomControls(context, theme),
              _buildCameraWidget(context, theme),
              _buildGamepadWidget(context, theme),
            ],
          ),
        );
  }

  Widget _buildTopMenuBar(BuildContext context, ThemeData theme) {
    return Positioned(
      left: 5,
      top: 1,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Linear velocity display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: RawChip(
                  avatar: Icon(
                    const IconData(0xe606, fontFamily: "Speed"),
                    color: Colors.green[400],
                  ),
                  label: ValueListenableBuilder<RobotSpeed>(
                    valueListenable:
                        Provider.of<RosChannel>(context, listen: true)
                            .robotSpeed_,
                    builder: (context, speed, child) {
                      return Text('${(speed.vx).toStringAsFixed(2)} m/s');
                    },
                  ),
                ),
              ),
              // Angular velocity display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: RawChip(
                  avatar: const Icon(IconData(0xe680, fontFamily: "Speed")),
                  label: ValueListenableBuilder<RobotSpeed>(
                    valueListenable:
                        Provider.of<RosChannel>(context, listen: true)
                            .robotSpeed_,
                    builder: (context, speed, child) {
                      return Text(
                          '${rad2deg(speed.vw).toStringAsFixed(2)} deg/s');
                    },
                  ),
                ),
              ),
              // Battery level display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: RawChip(
                  avatar: Icon(
                    const IconData(0xe995, fontFamily: "Battery"),
                    color: Colors.amber[300],
                  ),
                  label: ValueListenableBuilder<double>(
                    valueListenable:
                        Provider.of<RosChannel>(context, listen: false)
                            .battery_,
                    builder: (context, battery, child) {
                      return Text('${battery.toStringAsFixed(0)} %');
                    },
                  ),
                ),
              ),
              // Navigation status display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: RawChip(
                  avatar: const Icon(
                    Icons.navigation,
                    color: Colors.green,
                    size: 16,
                  ),
                  label: ValueListenableBuilder<ActionStatus>(
                    valueListenable:
                        Provider.of<RosChannel>(context, listen: true)
                            .navStatus_,
                    builder: (context, navStatus, child) {
                      return Text('${navStatus.toString()}');
                    },
                  ),
                ),
              ),
              // Diagnostic status display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Consumer<RosChannel>(
                  builder: (context, rosChannel, child) {
                    final diagnosticManager = rosChannel.diagnosticManager;
                    final statusCounts = diagnosticManager.getStatusCounts();
                    
                    int errorCount = statusCounts[DiagnosticStatus.ERROR] ?? 0;
                    int warnCount = statusCounts[DiagnosticStatus.WARN] ?? 0;
                    
                    Color chipColor = Colors.green;
                    IconData chipIcon = Icons.check_circle;
                    String chipText = 'Normal';
                    
                    if (errorCount > 0) {
                      chipColor = Colors.red;
                      chipIcon = Icons.error;
                      chipText = 'Error: $errorCount';
                    } else if (warnCount > 0) {
                      chipColor = Colors.orange;
                      chipIcon = Icons.warning;
                      chipText = 'Warning: $warnCount';
                    }
                    
                    return  RawChip(
                          avatar: Icon(
                            chipIcon,
                            color: chipColor,
                            size: 16,
                          ),
                          label: Text(chipText),
                          backgroundColor: chipColor.withOpacity(0.1),
                          elevation: 0,
                          onPressed: () {
                             Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DiagnosticPage(),
                            ),
                          );
                        },

                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftToolbar(BuildContext context, ThemeData theme) {
    return Positioned(
      left: 5,
      top: 60,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Layer toggle control
          Card(
            elevation: 10,
            child: Container(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.layers),
                    color:
                        showLayerControl ? Colors.green : theme.iconTheme.color,
                    onPressed: () {
                      setState(() {
                        showLayerControl = !showLayerControl;
                      });
                    },
                  ),
                  if (showLayerControl) ...[
                    // Use loop to generate layer control buttons
                    ...Provider.of<GlobalState>(context, listen: true).layerNames.map((layerName) {
                      // Define icon and color configuration for each layer
                      final layerConfig = <String, Map<String, dynamic>>{
                        'showGrid': {
                          'icon': Icons.grid_on,
                          'iconOff': Icons.grid_off,
                          'color': Colors.green,
                          'tooltip': 'Grid Layer',
                        },
                        'showGlobalCostmap': {
                          'icon': Icons.map,
                          'iconOff': Icons.map_outlined,
                          'color': Colors.green,
                          'tooltip': 'Global Costmap',
                        },
                        'showLocalCostmap': {
                          'icon': Icons.map_outlined,
                          'iconOff': Icons.map_outlined,
                          'color': Colors.green,
                          'tooltip': 'Local Costmap',
                        },
                        'showLaser': {
                          'icon': Icons.radar,
                          'iconOff': Icons.radar_outlined,
                          'color': Colors.green,
                          'tooltip': 'Laser Data',
                        },
                        'showPointCloud': {
                          'icon': Icons.cloud,
                          'iconOff': Icons.cloud_outlined,
                          'color': Colors.green,
                          'tooltip': 'Point Cloud Data',
                        },
                        'showGlobalPath': {
                          'icon': Icons.timeline,
                          'iconOff': Icons.timeline_outlined,
                          'color': Colors.blue,
                          'tooltip': 'Global Path',
                        },
                        'showLocalPath': {
                          'icon': Icons.timeline,
                          'iconOff': Icons.timeline_outlined,
                          'color': Colors.green,
                          'tooltip': 'Local Path',
                        },
                        'showTracePath': {
                          'icon': Icons.timeline,
                          'iconOff': Icons.timeline_outlined,
                          'color': Colors.yellow,
                          'tooltip': 'Trace Path',
                        },
                        'showTopology': {
                          'icon': Icons.account_tree,
                          'iconOff': Icons.account_tree_outlined,
                          'color': Colors.orange,
                          'tooltip': 'Topology Map',
                        },
                        'showRobotFootprint': {
                          'icon': Icons.smart_toy,
                          'iconOff': Icons.smart_toy_outlined,
                          'color': Colors.blue,
                          'tooltip': 'Robot Footprint',
                        },
                      };
                      
                      final config = layerConfig[layerName];
                      if (config == null) return const SizedBox.shrink();
                      
                      return Tooltip(
                        message: config['tooltip'] as String,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: Provider.of<GlobalState>(context, listen: true).getLayerState(layerName),
                          builder: (context, isVisible, child) {
                            return IconButton(
                              icon: Icon(
                                isVisible ? config['icon'] as IconData : config['iconOff'] as IconData,
                                size: 20,
                              ),
                              color: isVisible ? config['color'] as Color : Colors.grey,
                              onPressed: () {
                                Provider.of<GlobalState>(context, listen: false).toggleLayer(layerName);
                              },
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
          ),

          // Relocalization tool
          Card(
            elevation: 10,
            child: Container(
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      var globalState =
                          Provider.of<GlobalState>(context, listen: false);
                      if (globalState.mode.value == Mode.reloc) {
                        globalState.mode.value = Mode.normal;
                      } else {
                        globalState.mode.value = Mode.reloc;
                      }
                      game.setRelocMode(globalState.mode.value == Mode.reloc);
                      setState(() {});
                    },
                    icon: Icon(
                      const IconData(0xe60f, fontFamily: "Reloc"),
                      color: Provider.of<GlobalState>(context, listen: false)
                                  .mode
                                  .value ==
                              Mode.reloc
                          ? Colors.green
                          : theme.iconTheme.color,
                    ),
                  ),
                  if (Provider.of<GlobalState>(context, listen: false)
                          .mode
                          .value ==
                      Mode.reloc) ...[
                    IconButton(
                      onPressed: () {
                        // Confirm relocation logic
                        Provider.of<GlobalState>(context, listen: false)
                            .mode
                            .value = Mode.normal;
                        game.setRelocMode(false);
                        Provider.of<RosChannel>(context, listen: false).sendRelocPose(game.getRelocRobotPose());
                        setState(() {});
                      },
                      icon: Icon(Icons.check, color: Colors.green),
                    ),
                    IconButton(
                      onPressed: () {
                        // Cancel relocation logic
                        Provider.of<GlobalState>(context, listen: false)
                            .mode
                            .value = Mode.normal;
                        game.setRelocMode(false);
                        setState(() {});
                      },
                      icon: Icon(Icons.close, color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Display camera image
          Card(
            elevation: 10,
            child: IconButton(
              icon: Icon(Icons.camera_alt),
              color: showCamera ? Colors.green : theme.iconTheme.color,
              onPressed: () {
                setState(() {
                  showCamera = !showCamera;
                });
              },
              tooltip: 'Camera Image',
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Manual control
          Card(
            elevation: 10,
            child: IconButton(
              icon: Icon(
                const IconData(0xea45, fontFamily: "GamePad"),
                color: Provider.of<GlobalState>(context, listen: false)
                        .isManualCtrl
                        .value
                    ? Colors.green
                    : theme.iconTheme.color,
              ),
              onPressed: () {
                if (Provider.of<GlobalState>(context, listen: false)
                    .isManualCtrl
                    .value) {
                  Provider.of<GlobalState>(context, listen: false)
                      .isManualCtrl
                      .value = false;
                  Provider.of<RosChannel>(context, listen: false)
                      .stopMunalCtrl();
                  setState(() {});
                } else {
                  Provider.of<GlobalState>(context, listen: false)
                      .isManualCtrl
                      .value = true;
                  Provider.of<RosChannel>(context, listen: false)
                      .startMunalCtrl();
                  setState(() {});
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightToolbar(BuildContext context, ThemeData theme) {
    return Positioned(
      right: 5,
      top: 30,
      child: Row(
        children: [
          // Right side information panel
          if (game.showInfoPanel && selectedNavPoint != null)
            Container(
              width: 300, // Fixed width, doesn't fill entire right side
              child: Card(
                elevation: 16,
                shadowColor: Colors.black.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Colors.blue[50]!,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0), // Reduce padding
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, // Auto-size based on content
                      children: [
                        // Title bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6), // Reduce icon container size
                                  decoration: BoxDecoration(
                                    color: Colors.blue[100],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.location_on,
                                    color: Colors.blue[700],
                                    size: 20, // Reduce icon size
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Navigation Point Info',
                                  style: theme.textTheme.titleMedium?.copyWith( // Use smaller title style
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
                            // Add close button
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  game.hideInfoPanel();
                                  setState(() {
                                    selectedNavPoint = null;
                                  });
                                },
                                tooltip: 'Close',
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Divider(height: 20, thickness: 1, color: Colors.grey[300]), // Reduce divider height
                        
                        // Navigation point name and type
                        Container(
                          padding: const EdgeInsets.all(12), // Reduce padding
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.blue[200]!, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue[100]!.withOpacity(0.3),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.label,
                                  color: Colors.blue[700],
                                  size: 16, // Reduce icon size
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedNavPoint!.name,
                                      style: theme.textTheme.bodyLarge?.copyWith( // Use smaller text style
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _getTypeColor(selectedNavPoint!.type),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _getTypeColor(selectedNavPoint!.type).withOpacity(0.3),
                                            blurRadius: 3,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _getTypeText(selectedNavPoint!.type),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16), // Reduce spacing
                        
                        // Coordinate information
                        _buildInfoSection(
                          context,
                          theme,
                          'Position Coordinates',
                          Icons.gps_fixed,
                          [
                            _buildInfoRow('X Coordinate', '${selectedNavPoint!.x.toStringAsFixed(2)} m'),
                            _buildInfoRow('Y Coordinate', '${selectedNavPoint!.y.toStringAsFixed(2)} m'),
                            _buildInfoRow('Orientation', '${(selectedNavPoint!.theta * 180 / 3.14159).toStringAsFixed(1)}°'),
                          ],
                        ),
                        
                        const SizedBox(height: 16), // Reduce spacing
                        
                        // Navigation button
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue[400]!.withOpacity(0.3),
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if(Provider.of<GlobalState>(context, listen: false).isManualCtrl.value){
                                toastification.show(
                                  context: context,
                                  title: Text('Please stop manual control first'),
                                  autoCloseDuration: const Duration(seconds: 3),
                                );
                                return;
                              }
                              
                              // Use RosChannel to send navigation goal
                              Provider.of<RosChannel>(context, listen: false).sendNavigationGoal(
                                RobotPose(
                                  selectedNavPoint!.x, 
                                  selectedNavPoint!.y, 
                                  selectedNavPoint!.theta
                                )
                              );
                              
                              // Use fluttertoast to show success message
                              toastification.show(
                                context: context,
                                title: Text('Navigation goal sent to ${selectedNavPoint!.name}'),
                                autoCloseDuration: const Duration(seconds: 3),
                              );
                              
                              // Automatically close info panel after sending navigation goal
                              game.hideInfoPanel();
                              setState(() {
                                selectedNavPoint = null;
                              });
                            },
                            icon: const Icon(Icons.navigation, size: 20),
                            label: const Text(
                              'Send Navigation Goal',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600), // Reduce button text size
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14), // Reduce button height
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          
          // Original toolbar buttons
          Column(
            children: [
              // Map edit button
              Card(
                elevation: 10,
                child: IconButton(
                  icon: Icon(
                    Icons.edit_document,
                    color: (Provider.of<GlobalState>(context, listen: false)
                                .mode
                                .value ==
                            Mode.mapEdit)
                        ? Colors.orange
                        : theme.iconTheme.color,
                  ),
                  onPressed: () {
                     Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapEditPage(
                            onExit: () {
                              // Reload data when exiting map edit interface
                              _reloadData();
                            },
                          ),
                        ),
                      );
                    setState(() {});
                  },
                  tooltip: 'Map Editor',
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Zoom in button
              Card(
                elevation: 10,
                child: IconButton(
                  onPressed: () {
                    game.zoomIn();
                  },
                  icon: Icon(
                    Icons.zoom_in,
                    color: theme.iconTheme.color,
                  ),
                  tooltip: 'Zoom In',
                ),
              ),
              // Zoom out button
              Card(
                elevation: 10,
                child: IconButton(
                  onPressed: () {
                    game.zoomOut();
                  },
                  icon: Icon(
                    Icons.zoom_out,
                    color: theme.iconTheme.color,
                  ),
                  tooltip: 'Zoom Out',
                ),
              ),
              // Center on robot button
              Card(
                elevation: 10,
                child: IconButton(
                  onPressed: () {
                    var globalState =
                        Provider.of<GlobalState>(context, listen: false);
                    if (globalState.mode.value == Mode.robotFixedCenter) {
                      globalState.mode.value = Mode.normal;
                      game.centerOnRobot(false);
                    } else {
                      globalState.mode.value = Mode.robotFixedCenter;
                      game.centerOnRobot(true);
                    }
                    setState(() {});
                  },
                  icon: Icon(
                    Icons.location_searching,
                    color:
                        Provider.of<GlobalState>(context, listen: false).mode.value ==
                                Mode.robotFixedCenter
                            ? Colors.green
                            : theme.iconTheme.color,
                  ),
                ),
              ),
              // // Exit button
              // Card(
              //   elevation: 10,
              //   child: IconButton(
              //     onPressed: () {
              //       Navigator.push(context, MaterialPageRoute(builder: (context) => ConnectPage()));
              //     },
              //     icon: Icon(
              //       Icons.exit_to_app,
              //       color: theme.iconTheme.color,
              //     ),
              //     tooltip: 'Exit',
              //   ),
              // ),
                             // Remove GamepadWidget from here, we'll move it to the bottom of the screen
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context, ThemeData theme) {
    return Positioned(
      left: 5,
      bottom: 10,
      child: Consumer<GlobalState>(
        builder: (context, globalState, child) {
          return Visibility(
            visible: !globalState.isManualCtrl.value,
            child: Row(
              children: [
                // Emergency stop button
                Card(
                  color: Colors.red,
                  child: Container(
                    width: 100,
                    height: 50,
                    child: TextButton(
                      child: const Text(
                        "STOP",
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: () {
                        Provider.of<RosChannel>(context, listen: false)
                            .sendEmergencyStop();
                        toastification.show(
                          context: context,
                          title: Text('Emergency stop triggered'),
                          autoCloseDuration: const Duration(seconds: 3),
                        );
                      },
                    ),
                  ),
                ),
                // Stop navigation button
                Consumer<RosChannel>(
                  builder: (context, rosChannel, child) {
                    return ValueListenableBuilder<ActionStatus>(
                      valueListenable: rosChannel.navStatus_,
                      builder: (context, navStatus, child) {
                        return Visibility(
                          visible: navStatus == ActionStatus.executing ||
                              navStatus == ActionStatus.accepted,
                          child: Card(
                            color: Colors.blue,
                            child: Container(
                              width: 50,
                              height: 50,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.stop_circle,
                                  size: 30,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  Provider.of<RosChannel>(context,
                                          listen: false)
                                      .sendCancelNav();
                                  toastification.show(
                                    context: context,
                                    title: Text('Navigation stopped'),
                                    autoCloseDuration: const Duration(seconds: 3),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, ThemeData theme, String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.grey[600], size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label, 
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          Text(
            value, 
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }


  Color _getTypeColor(NavPointType type) {
    switch (type) {
      case NavPointType.navGoal:
        return Colors.blue[600]!;
      case NavPointType.chargeStation:
        return Colors.green[600]!;
    }
  }

  String _getTypeText(NavPointType type) {
    switch (type) {
      case NavPointType.navGoal:
        return 'Navigation Goal';
      case NavPointType.chargeStation:
        return 'Charging Station';
    }
  }
  
  // Build camera display component
  Widget _buildCameraWidget(BuildContext context, ThemeData theme) {
    if (!showCamera) return const SizedBox.shrink();
    
    final screenSize = MediaQuery.of(context).size;
    
    return Positioned(
      left: camPosition.dx,
      top: camPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          if (!isCamFullscreen) {
            setState(() {
              double newX = camPosition.dx + details.delta.dx;
              double newY = camPosition.dy + details.delta.dy;
              // Limit position within screen bounds
              newX = newX.clamp(0.0, screenSize.width - camWidgetWidth);
              newY = newY.clamp(0.0, screenSize.height - camWidgetHeight);
              camPosition = Offset(newX, newY);
            });
          }
        },
        child: Container(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // Get screen dimensions in non-fullscreen mode
                  double containerWidth = isCamFullscreen
                      ? screenSize.width
                      : camWidgetWidth;
                  double containerHeight = isCamFullscreen
                      ? screenSize.height
                      : camWidgetHeight;

                  return Mjpeg(
                    stream: 'http://${globalSetting.robotIp}:${globalSetting.imagePort}/stream?topic=${globalSetting.imageTopic}',
                    isLive: true,
                    width: containerWidth,
                    height: containerHeight,
                    fit: BoxFit.fill,
                  );
                },
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  icon: Icon(
                    isCamFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    color: Colors.black,
                  ),
                  constraints: BoxConstraints(), // Remove button's default size constraints for more compact design
                  onPressed: () {
                    setState(() {
                      isCamFullscreen = !isCamFullscreen;
                      if (isCamFullscreen) {
                        // When entering fullscreen, save current position and set position to (0, 0)
                        camPreviousPosition = camPosition;
                        camPosition = Offset(0, 0);
                      } else {
                        // When exiting fullscreen, restore previous position
                        camPosition = camPreviousPosition;
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Build gamepad component
  Widget _buildGamepadWidget(BuildContext context, ThemeData theme) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: 150, // Give GamepadWidget a specific height
        child: GamepadWidget(),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}




