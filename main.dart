import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const JalanGoApp());

class JalanGoApp extends StatelessWidget {
  const JalanGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF102A43);
    const green = Color(0xFF087F5B);
    return MaterialApp(
      title: 'JalanGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: green, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF6F8FA),
        appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white),
        useMaterial3: true,
      ),
      home: const MapHome(),
    );
  }
}

class MapHome extends StatefulWidget {
  const MapHome({super.key});

  @override
  State<MapHome> createState() => _MapHomeState();
}

class _MapHomeState extends State<MapHome> {
  final MapController _mapController = MapController();
  final TextEditingController _destinationController = TextEditingController();
  LatLng _center = const LatLng(3.1390, 101.6869); // Kuala Lumpur starter view
  bool _darkMap = false;
  bool _busy = false;
  LatLng? _currentLocation;
  LatLng? _destinationPoint;
  List<LatLng> _routePoints = [];
  String _status = 'Ready to explore Malaysia';
  final List<_RoadReport> _reports = [
    _RoadReport('Road hazard', const LatLng(3.145, 101.693), Icons.warning_amber_rounded),
    _RoadReport('Traffic', const LatLng(3.132, 101.679), Icons.traffic_rounded),
  ];

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _status = 'Location permission is needed to show your position.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      _mapController.move(point, 15);
      setState(() {
        _center = point;
        _currentLocation = point;
        _status = 'Showing your current location';
      });
    } catch (_) {
      setState(() => _status = 'Could not get location. Check GPS and permissions.');
    }
  }

  Future<void> _searchDestination() async {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
      setState(() => _status = 'Enter a destination to search.');
      return;
    }
    setState(() { _busy = true; _status = 'Searching for "$destination"…'; });
    try {
      // Nominatim is suitable for a prototype only. A public launch needs a compliant provider.
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': '$destination, Malaysia', 'format': 'jsonv2', 'limit': '1',
        'addressdetails': '1',
      });
      final response = await http.get(uri, headers: {
        'User-Agent': 'JalanGo/0.1 (Android navigation prototype)',
        'Accept-Language': 'en,ms',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Search service returned ${response.statusCode}');
      final results = jsonDecode(response.body) as List<dynamic>;
      if (results.isEmpty) {
        setState(() { _busy = false; _status = 'No result found. Try adding a town or state.'; });
        return;
      }
      final item = results.first as Map<String, dynamic>;
      final target = LatLng(double.parse(item['lat'] as String), double.parse(item['lon'] as String));
      final start = _currentLocation ?? _center;
      final routeUri = Uri.https('router.project-osrm.org', '/route/v1/driving/${start.longitude},${start.latitude};${target.longitude},${target.latitude}', {
        'overview': 'full', 'geometries': 'geojson', 'steps': 'true',
      });
      final routeResponse = await http.get(routeUri, headers: {
        'User-Agent': 'JalanGo/0.1 (Android navigation prototype)',
      }).timeout(const Duration(seconds: 20));
      if (routeResponse.statusCode != 200) throw Exception('Routing service returned ${routeResponse.statusCode}');
      final routeData = jsonDecode(routeResponse.body) as Map<String, dynamic>;
      final routes = routeData['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty) throw Exception('No driving route was found.');
      final route = routes.first as Map<String, dynamic>;
      final coordinates = ((route['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>);
      final points = coordinates.map((coord) {
        final pair = coord as List<dynamic>;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
      final distanceKm = ((route['distance'] as num).toDouble() / 1000).toStringAsFixed(1);
      final minutes = ((route['duration'] as num).toDouble() / 60).round();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _destinationPoint = target;
        _routePoints = points;
        _status = 'Route: $distanceKm km · about $minutes min. ${_currentLocation == null ? 'Start is the current map centre; tap My location for a route from GPS.' : 'Route starts from your GPS location.'}';
      });
      _mapController.move(target, 13);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _status = 'Could not find a route. Check internet and try again.'; });
    }
  }

  void _addReport() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Report a road issue', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _reportButton(context, 'Traffic', Icons.traffic_rounded),
              _reportButton(context, 'Accident', Icons.car_crash_rounded),
              _reportButton(context, 'Hazard', Icons.warning_amber_rounded),
              _reportButton(context, 'Flood', Icons.flood_rounded),
              _reportButton(context, 'Roadworks', Icons.construction_rounded),
              _reportButton(context, 'Pothole', Icons.tire_repair_rounded),
            ]),
            const SizedBox(height: 12),
            const Text('Prototype only: reports are not sent to a server or shared with other drivers yet.'),
          ]),
        ),
      ),
    );
  }

  Widget _reportButton(BuildContext sheetContext, String label, IconData icon) => FilledButton.tonalIcon(
    onPressed: () {
      Navigator.pop(sheetContext);
      setState(() => _status = '$label report selected. Community service is not connected yet.');
    },
    icon: Icon(icon), label: Text(label),
  );

  @override
  Widget build(BuildContext context) {
    final tiles = _darkMap
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.navigation_rounded, color: Color(0xFF087F5B))),
          const SizedBox(width: 10),
          const Text('JalanGo', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .3)),
        ]),
        actions: [IconButton(tooltip: 'Switch map theme', onPressed: () => setState(() => _darkMap = !_darkMap), icon: Icon(_darkMap ? Icons.light_mode : Icons.dark_mode))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _destinationController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchDestination(),
              decoration: InputDecoration(
                hintText: 'Where to?  e.g. Johor Bahru',
                prefixIcon: const Icon(Icons.search),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            )),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy ? null : _searchDestination, style: FilledButton.styleFrom(padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward_rounded)),
          ]),
        ),
        Expanded(child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _center, initialZoom: 12, onPositionChanged: (position, hasGesture) { if (position.center != null) _center = position.center!; }),
          children: [
            TileLayer(
              urlTemplate: tiles,
              subdomains: _darkMap ? const ['a', 'b', 'c', 'd'] : const [],
              userAgentPackageName: 'my.jalango.app',
              tileProvider: NetworkTileProvider(),
            ),
            if (_routePoints.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _routePoints, strokeWidth: 5, color: const Color(0xFF087F5B))]),
            if (_destinationPoint != null) MarkerLayer(markers: [Marker(point: _destinationPoint!, width: 48, height: 48, child: const Icon(Icons.location_pin, color: Color(0xFFB42318), size: 44))]),
            MarkerLayer(markers: _reports.map((r) => Marker(
              point: r.point, width: 44, height: 44,
              child: Tooltip(message: r.label, child: Container(
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(.18), blurRadius: 8)]),
                child: Icon(r.icon, color: const Color(0xFFB42318), size: 25),
              )),
            )).toList()),
            RichAttributionWidget(attributions: [
              TextSourceAttribution('OpenStreetMap contributors', onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'))),
            ]),
          ],
        )),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.info_outline, size: 18, color: Color(0xFF087F5B)), const SizedBox(width: 8), Expanded(child: Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)))]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _goToMyLocation, icon: const Icon(Icons.my_location), label: const Text('My location'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.icon(onPressed: _addReport, icon: const Icon(Icons.add_alert_rounded), label: const Text('Report issue'))),
            ]),
            const SizedBox(height: 6),
            const Text('Prototype routing uses public demo services. Turn-by-turn and live reports are not active.', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
      ]),
    );
  }
}

class _RoadReport {
  final String label;
  final LatLng point;
  final IconData icon;
  const _RoadReport(this.label, this.point, this.icon);
}
