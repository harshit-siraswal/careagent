import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Provides Firebase ID tokens for backend API calls.
typedef IdTokenProvider = Future<String?> Function();

/// Small typed client for the CareAgent pilot backend API.
class CareAgentApiClient {
  /// Creates a backend API client.
  CareAgentApiClient({
    required this.config,
    required this.idTokenProvider,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Runtime app config.
  final AppConfig config;

  /// Supplies Firebase ID tokens.
  final IdTokenProvider idTokenProvider;

  /// Role selected at sign-in and sent to backend auth/session boundaries.
  String careAgentRole = 'patient';

  final http.Client _httpClient;

  /// Whether API calls are enabled.
  bool get isConfigured => config.hasApiBaseUrl;

  /// Loads the current backend identity.
  Future<Map<String, dynamic>> me() => _request('GET', '/me');

  /// Creates a patient profile.
  Future<Map<String, dynamic>> createPatient({
    required String fullName,
    String primaryLanguage = 'en',
  }) {
    return _request(
      'POST',
      '/patients',
      body: {'full_name': fullName, 'primary_language': primaryLanguage},
    );
  }

  /// Lists visible patient profiles.
  Future<List<Map<String, dynamic>>> listPatients() async {
    final payload = await _request('GET', '/patients');
    return _items(payload);
  }

  /// Lists consents for a patient.
  Future<List<Map<String, dynamic>>> listConsents(String patientId) async {
    final payload = await _request('GET', '/patients/$patientId/consents');
    return _items(payload);
  }

  /// Grants a patient consent.
  Future<Map<String, dynamic>> grantConsent({
    required String patientId,
    required String consentType,
    required Map<String, dynamic> scope,
  }) {
    return _request(
      'POST',
      '/patients/$patientId/consents',
      body: {
        'consent_type': consentType,
        'scope': scope,
        'consent_text_version': 'pilot-v1',
        'reason': 'pilot onboarding',
      },
    );
  }

  /// Revokes a patient consent.
  Future<Map<String, dynamic>> revokeConsent({
    required String patientId,
    required String consentId,
    required String reason,
  }) {
    return _request(
      'POST',
      '/patients/$patientId/consents/$consentId/revoke',
      body: {'reason': reason},
    );
  }

  /// Submits a single manual vital reading.
  Future<Map<String, dynamic>> submitManualVital({
    required String patientId,
    required String metricCode,
    required num value,
    required String unit,
  }) {
    return _request(
      'POST',
      '/patients/$patientId/observations',
      body: {
        'observations': [
          {
            'metric_code': metricCode,
            'value': value,
            'unit': unit,
            'source_type': 'manual',
            'reliability_tier': 'manual_or_ocr',
            'observed_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      },
    );
  }

  /// Loads latest vitals.
  Future<List<Map<String, dynamic>>> latestVitals(String patientId) async {
    final payload = await _request('GET', '/patients/$patientId/vitals/latest');
    final readings = payload['readings'];
    if (readings is! List) return const [];
    return readings.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  /// Creates a pilot risk event.
  Future<Map<String, dynamic>> createRiskEvent({
    required String patientId,
    required String reason,
  }) {
    return _request(
      'POST',
      '/patients/$patientId/risk-events',
      body: {
        'severity': 'high',
        'confidence': 0.94,
        'reason': reason,
        'evidence': [
          {'source': 'hackathon_demo_manual_vitals'},
        ],
        'recommended_action': 'start_escalation_protocol',
      },
    );
  }

  /// Lists patient alerts.
  Future<List<Map<String, dynamic>>> listAlerts(String patientId) async {
    final payload = await _request('GET', '/patients/$patientId/alerts');
    return _items(payload);
  }

  /// Creates a simulation-only escalation policy.
  Future<Map<String, dynamic>> createSimulationPolicy(String patientId) {
    return _request(
      'POST',
      '/patients/$patientId/escalation-policies',
      body: {
        'name': 'Hackathon multi-contact simulation policy',
        'severity_trigger': 'high',
        'simulation_mode': true,
        'emergency_enabled': false,
        'location_sharing_enabled': false,
        'steps': [
          {
            'step_order': 1,
            'action_type': 'patient_prompt',
            'channel': 'in_app',
            'target_role': 'caretaker',
            'timeout_seconds': 60,
            'retry_count': 0,
            'include_location': false,
          },
          {
            'step_order': 2,
            'action_type': 'send_message',
            'channel': 'whatsapp',
            'target_role': 'caretaker',
            'template_id': 'critical_escalation_caretaker_v1',
            'timeout_seconds': 120,
            'retry_count': 1,
            'include_location': false,
          },
          {
            'step_order': 3,
            'action_type': 'send_message',
            'channel': 'telegram',
            'target_role': 'family',
            'template_id': 'telegram_ack_callback_v1',
            'timeout_seconds': 120,
            'retry_count': 1,
            'include_location': false,
          },
          {
            'step_order': 4,
            'action_type': 'place_call',
            'channel': 'voice',
            'target_role': 'caretaker',
            'template_id': 'critical_caretaker_call_v1',
            'timeout_seconds': 180,
            'retry_count': 1,
            'include_location': false,
          },
          {
            'step_order': 5,
            'action_type': 'place_call',
            'channel': 'voice',
            'target_role': 'doctor',
            'template_id': 'doctor_escalation_call_v1',
            'timeout_seconds': 180,
            'retry_count': 0,
            'include_location': false,
          },
        ],
      },
    );
  }

  /// Starts a simulation escalation for a risk event.
  Future<Map<String, dynamic>> startSimulationEscalation({
    required String riskEventId,
    required String patientId,
    required String policyId,
  }) {
    return _request(
      'POST',
      '/risk-events/$riskEventId/escalate',
      headers: {
        'Idempotency-Key': 'pilot-escalation-$riskEventId-$policyId',
        'X-CareAgent-Patient-Id': patientId,
      },
      body: {
        'policy_id': policyId,
        'requested_by': 'patient',
        'simulation_mode': true,
        'reason': 'pilot simulation',
      },
    );
  }

  /// Acknowledges a simulation escalation.
  Future<Map<String, dynamic>> acknowledgeEscalation({
    required String escalationRunId,
    required String patientId,
  }) {
    return _request(
      'POST',
      '/escalation-runs/$escalationRunId/acknowledge',
      headers: {'X-CareAgent-Patient-Id': patientId},
      body: {'note': 'Acknowledged in pilot app.'},
    );
  }

  /// Initializes a placeholder document upload session.
  Future<Map<String, dynamic>> initDocumentUpload(String patientId) {
    return _request(
      'POST',
      '/patients/$patientId/documents',
      headers: {
        'Idempotency-Key':
            'pilot-document-${DateTime.now().millisecondsSinceEpoch}',
      },
      body: {
        'original_filename': 'pilot-note.pdf',
        'file_type': 'application/pdf',
        'file_size_bytes': 1024,
        'sha256': DateTime.now().microsecondsSinceEpoch.toString(),
        'upload_channel': 'in_app',
        'document_type_hint': 'pilot_note',
      },
    );
  }

  /// Loads patient audit logs.
  Future<List<Map<String, dynamic>>> auditLogs(String patientId) async {
    final payload = await _request('GET', '/patients/$patientId/audit-logs');
    return _items(payload);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    if (!isConfigured) {
      throw const CareAgentApiException('Backend API URL is not configured.');
    }
    final token = await idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const CareAgentApiException('Sign in before calling the backend.');
    }

    final uri = Uri.parse(
      '${config.apiBaseUrl.replaceAll(RegExp(r"/$"), "")}$path',
    );
    final requestHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'X-CareAgent-Role': careAgentRole,
      ...?headers,
    };

    final response = switch (method) {
      'GET' => await _httpClient.get(uri, headers: requestHeaders),
      'POST' => await _httpClient.post(
        uri,
        headers: requestHeaders,
        body: jsonEncode(body ?? const {}),
      ),
      'PATCH' => await _httpClient.patch(
        uri,
        headers: requestHeaders,
        body: jsonEncode(body ?? const {}),
      ),
      _ => throw CareAgentApiException('Unsupported method $method.'),
    };

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] ?? decoded['detail'];
      throw CareAgentApiException(
        error is Map ? error.toString() : response.body,
      );
    }
    return decoded;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> payload) {
    final rawItems = payload['items'];
    if (rawItems is! List) return const [];
    return rawItems.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }
}

/// Backend API failure safe for display.
class CareAgentApiException implements Exception {
  /// Creates a backend API exception.
  const CareAgentApiException(this.message);

  /// Safe user-facing message.
  final String message;

  @override
  String toString() => message;
}
