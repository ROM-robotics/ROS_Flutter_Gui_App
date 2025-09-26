import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:ros_flutter_gui_app/basic/diagnostic_status.dart';
import 'package:ros_flutter_gui_app/provider/diagnostic_manager.dart';

class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({super.key});

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  late RosChannel rosChannel;
  String _searchQuery = '';
  int _filterLevel = -1; // -1: All, 0: OK, 1: WARN, 2: ERROR, 3: STALE
  Map<String, bool> _expandedHardware = {}; // Hardware ID expansion state
  Map<String, Map<String, bool>> _expandedComponents = {}; // Component expansion state
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    rosChannel = Provider.of<RosChannel>(context, listen: false);
    _searchController = TextEditingController(text: _searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Diagnostics'),
        // backgroundColor: Colors.blue,
        // foregroundColor: Colors.white,
        actions: [
          _buildSummaryBar(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: Consumer<RosChannel>(
              builder: (context, rosChannel, child) {
                return ListenableBuilder(
                  listenable: rosChannel.diagnosticManager,
                  builder: (context, child) {
                    final diagnosticManager = rosChannel.diagnosticManager;
                    final filteredData = _getFilteredData(diagnosticManager);
                    
                    if (filteredData.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty || _filterLevel != -1
                                  ? 'No matching diagnostic data found'
                                  : 'No diagnostic data available',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                            if (_searchQuery.isNotEmpty || _filterLevel != -1) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _filterLevel = -1;
                                    _searchController.clear();
                                  });
                                },
                                child: const Text('Clear Filter'),
                              ),
                            ],
                          ],
                        ),
                      );
                    }
                
                return Column(
                  children: [
                        // Filter result statistics
                        if (_searchQuery.isNotEmpty || _filterLevel != -1)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.filter_list, color: Colors.blue[600], size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Showing ${filteredData.length} hardware groups',
                                  style: TextStyle(
                                    color: Colors.blue[800],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _searchQuery = '';
                                      _filterLevel = -1;
                                      _searchController.clear();
                                    });
                                  },
                                  child: const Text('Clear Filter'),
                                ),
                              ],
                            ),
                          ),
                        // Diagnostic data list
                    Expanded(
                          child: ListView.builder(
                            itemCount: filteredData.length,
                            itemBuilder: (context, index) {
                              final entry = filteredData[index];
                              return _buildHardwareGroup(entry.key, entry.value);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Search box
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search component name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              onEditingComplete: () {
                setState(() {
                  _searchQuery = _searchController.text.toLowerCase();
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          // Status filter
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Text('Filter by Status: '),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All', -1),
                        const SizedBox(width: 8),
                        _buildFilterChip('OK', 0),
                        const SizedBox(width: 8),
                        _buildFilterChip('Warning', 1),
                        const SizedBox(width: 8),
                        _buildFilterChip('Error', 2),
                        const SizedBox(width: 8),
                        _buildFilterChip('Stale', 3),
                      ],
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty || _filterLevel != -1)
                  IconButton(
                    icon: const Icon(Icons.clear_all),
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                        _filterLevel = -1;
                        _searchController.clear();
                      });
                    },
                    tooltip: 'Clear all filters',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int level) {
    final isSelected = _filterLevel == level;
    Color color;
    
    switch (level) {
      case 0:
        color = Colors.green;
        break;
      case 1:
        color = Colors.orange;
        break;
      case 2:
        color = Colors.red;
        break;
      case 3:
        color = Colors.grey;
        break;
      default:
        color = Colors.blue;
    }

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterLevel = selected ? level : -1;
        });
      },
      selectedColor: color.withOpacity(0.2),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  // Get filtered data
  List<MapEntry<String, Map<String, DiagnosticState>>> _getFilteredData(DiagnosticManager diagnosticManager) {
    List<MapEntry<String, Map<String, DiagnosticState>>> allData = [];
    
    // Get all hardware data
    for (var hardwareId in diagnosticManager.hardwareIds) {
      final states = diagnosticManager.getStatesForHardware(hardwareId);
      allData.add(MapEntry(hardwareId, states));
    }
    
    // Apply search filter
      if (_searchQuery.isNotEmpty) {
      allData = allData.where((entry) {
        final hardwareId = entry.key.toLowerCase();
        final states = entry.value;
        
        // Check if hardware ID matches
        if (hardwareId.contains(_searchQuery)) {
          return true;
        }
        
        // Check if components match
        for (var componentEntry in states.entries) {
          final componentName = componentEntry.key.toLowerCase();
          final state = componentEntry.value;
          
          if (componentName.contains(_searchQuery) ||
              state.message.toLowerCase().contains(_searchQuery) ||
              state.keyValues.values.any((value) => value.toLowerCase().contains(_searchQuery))) {
            return true;
          }
        }
        
        return false;
      }).toList();
    }
    
    // Apply status filtering
    if (_filterLevel != -1) {
      allData = allData.where((entry) {
        final states = entry.value;
        
        // Check if there are components with matching status
        return states.values.any((state) => state.level == _filterLevel);
      }).toList();
    }
    
    return allData;
  }

  // Build hardware group
  Widget _buildHardwareGroup(String hardwareId, Map<String, DiagnosticState> states) {
    final isExpanded = _expandedHardware[hardwareId] ?? false;
    
    // If there are filter conditions, only show matching components
    Map<String, DiagnosticState> filteredStates = states;
    if (_searchQuery.isNotEmpty || _filterLevel != -1) {
      filteredStates = Map.fromEntries(
        states.entries.where((entry) {
          final componentName = entry.key;
          final state = entry.value;
          
      // Search filtering
      if (_searchQuery.isNotEmpty) {
            final hardwareIdLower = hardwareId.toLowerCase();
            final componentNameLower = componentName.toLowerCase();
            
            if (!hardwareIdLower.contains(_searchQuery) &&
                !componentNameLower.contains(_searchQuery) &&
                !state.message.toLowerCase().contains(_searchQuery) &&
                !state.keyValues.values.any((value) => value.toLowerCase().contains(_searchQuery))) {
          return false;
        }
      }

      // Status filtering
          if (_filterLevel != -1 && state.level != _filterLevel) {
        return false;
      }

      return true;
        })
      );
    }
    
    // If no matching components, don't show this hardware group
    if (filteredStates.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Calculate the highest status level for this hardware group
    int maxLevel = DiagnosticStatus.OK;
    for (var state in filteredStates.values) {
      if (state.level > maxLevel) {
        maxLevel = state.level;
      }
    }
    
    Color groupColor;
    IconData groupIcon;
    String groupStatusText;
    
    switch (maxLevel) {
      case DiagnosticStatus.ERROR:
        groupColor = Colors.red;
        groupIcon = Icons.error;
        groupStatusText = 'Error';
        break;
      case DiagnosticStatus.WARN:
        groupColor = Colors.orange;
        groupIcon = Icons.warning;
        groupStatusText = 'Warning';
        break;
      case DiagnosticStatus.STALE:
        groupColor = Colors.grey;
        groupIcon = Icons.schedule;
        groupStatusText = 'Stale';
        break;
      default:
        groupColor = Colors.green;
        groupIcon = Icons.check_circle;
        groupStatusText = 'OK';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: Icon(groupIcon, color: groupColor),
        title: Text(
          hardwareId,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: $groupStatusText | Components: ${filteredStates.length}',
              style: TextStyle(
                color: groupColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Last Updated: ${_formatDateTime(_getLatestUpdateTime(filteredStates))}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedHardware[hardwareId] = expanded;
          });
        },
        children: filteredStates.entries.map((entry) => _buildComponentItem(hardwareId, entry.key, entry.value)).toList(),
      ),
    );
  }

  // Build component item
  Widget _buildComponentItem(String hardwareId, String componentName, DiagnosticState state) {
    final isExpanded = _expandedComponents[hardwareId]?[componentName] ?? false;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Card(
        elevation: 2,
        child: ExpansionTile(
          leading: Icon(state.levelIcon, color: state.levelColor, size: 20),
          title: Text(
            componentName,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status: ${state.levelDisplayName}',
                style: TextStyle(
                  color: state.levelColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              if (state.message.isNotEmpty)
                Text(
                  state.message,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              Text(
                'Updated: ${_formatDateTime(state.lastUpdateTime)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              if (!_expandedComponents.containsKey(hardwareId)) {
                _expandedComponents[hardwareId] = {};
              }
              _expandedComponents[hardwareId]![componentName] = expanded;
            });
          },
          children: [
            if (state.keyValues.isNotEmpty)
              _buildKeyValueTable(state.keyValues, state.lastUpdateTime)
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'No detailed information available',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Last Updated: ${_formatDateTime(state.lastUpdateTime)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Build key-value table
  Widget _buildKeyValueTable(Map<String, String> keyValues, DateTime lastUpdateTime) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Key',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Value',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Updated: ${_formatDateTime(lastUpdateTime)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          ...keyValues.entries.map((entry) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: SizedBox(), // Placeholder for alignment
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // Build summary bar
  Widget _buildSummaryBar() {
    return Consumer<RosChannel>(
      builder: (context, rosChannel, child) {
        return ListenableBuilder(
          listenable: rosChannel.diagnosticManager,
          builder: (context, child) {
            final diagnosticManager = rosChannel.diagnosticManager;
            final statusCounts = diagnosticManager.getStatusCounts();
            
            if (statusCounts.values.every((count) => count == 0)) {
              return const SizedBox.shrink();
            }

            int okCount = statusCounts[DiagnosticStatus.OK] ?? 0;
            int warnCount = statusCounts[DiagnosticStatus.WARN] ?? 0;
            int errorCount = statusCounts[DiagnosticStatus.ERROR] ?? 0;
            int staleCount = statusCounts[DiagnosticStatus.STALE] ?? 0;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSummaryChip('OK', okCount, Colors.green),
                  const SizedBox(width: 4),
                  _buildSummaryChip('Warning', warnCount, Colors.orange),
                  const SizedBox(width: 4),
                  _buildSummaryChip('Error', errorCount, Colors.red),
                  const SizedBox(width: 4),
                  _buildSummaryChip('Stale', staleCount, Colors.grey),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Get the latest update time of all components in the hardware group
  DateTime _getLatestUpdateTime(Map<String, DiagnosticState> states) {
    if (states.isEmpty) return DateTime.now();
    
    DateTime latestTime = states.values.first.lastUpdateTime;
    for (var state in states.values) {
      if (state.lastUpdateTime.isAfter(latestTime)) {
        latestTime = state.lastUpdateTime;
      }
    }
    return latestTime;
  }

  // Format time display
  String _formatDateTime(DateTime dateTime) {
    final milliseconds = dateTime.millisecond.toString().padLeft(3, '0');
    return '${dateTime.year}-${dateTime.month}-${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}.$milliseconds';
  }
}
