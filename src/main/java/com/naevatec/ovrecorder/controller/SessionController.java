package com.naevatec.ovrecorder.controller;

import com.naevatec.ovrecorder.model.RecordingSession;
import com.naevatec.ovrecorder.service.SessionService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/sessions")
public class SessionController {

  private static final Logger logger = LoggerFactory.getLogger(SessionController.class);

  private final SessionService sessionService;

  public SessionController(SessionService sessionService) {
    this.sessionService = sessionService;
  }

  /**
   * Create a new recording session
   * POST /api/sessions
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! -X POST \
   * http://localhost:8080/api/sessions \
   * -H "Content-Type: application/json" \
   * -d
   * '{"sessionId":"rec-001","clientId":"client-01","clientHost":"192.168.1.100"}'
   */
  @PostMapping
  public ResponseEntity<?> createSession(@Valid @RequestBody CreateSessionRequest request,
      HttpServletRequest httpRequest) {
    try {
      String clientHost = request.getClientHost() != null ? request.getClientHost() : getClientIpAddress(httpRequest);

      RecordingSession session = sessionService.createSession(
          request.getSessionId(),
          request.getClientId(),
          clientHost);

      logger.info("Created session via API: {} from {}", session.getSessionId(), clientHost);
      return ResponseEntity.status(HttpStatus.CREATED).body(session);

    } catch (IllegalArgumentException e) {
      logger.warn("Failed to create session: {}", e.getMessage());
      return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    } catch (Exception e) {
      logger.error("Error creating session: {}", e.getMessage(), e);
      return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
          .body(Map.of("error", "Internal server error"));
    }
  }

  /**
   * Get session by ID
   * GET /api/sessions/{sessionId}
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/rec-001
   */
  @GetMapping("/{sessionId}")
  public ResponseEntity<?> getSession(@PathVariable String sessionId) {
    Optional<RecordingSession> session = sessionService.getSession(sessionId);

    if (session.isPresent()) {
      return ResponseEntity.ok(session.get());
    } else {
      return ResponseEntity.notFound().build();
    }
  }

  /**
   * Get all active sessions
   * GET /api/sessions
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions
   */
  @GetMapping
  public ResponseEntity<Map<String, Object>> getAllSessions() {
    List<RecordingSession> sessions = sessionService.getAllActiveSessions();
    long count = sessionService.getActiveSessionCount();

    Map<String, Object> response = new HashMap<>();
    response.put("sessions", sessions);
    response.put("count", count);
    response.put("timestamp", java.time.LocalDateTime.now());

    return ResponseEntity.ok(response);
  }

  /**
   * Update session heartbeat (keep-alive)
   * PUT /api/sessions/{sessionId}/heartbeat
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! -X PUT
   * http://localhost:8080/api/sessions/rec-001/heartbeat
   */
  @PutMapping("/{sessionId}/heartbeat")
  public ResponseEntity<?> updateHeartbeat(@PathVariable String sessionId) {
    boolean updated = sessionService.updateHeartbeat(sessionId);

    if (updated) {
      return ResponseEntity.ok(Map.of(
          "message", "Heartbeat updated",
          "sessionId", sessionId,
          "timestamp", java.time.LocalDateTime.now()));
    } else {
      return ResponseEntity.notFound().build();
    }
  }

  /**
   * Update session status
   * PUT /api/sessions/{sessionId}/status
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! -X PUT \
   * http://localhost:8080/api/sessions/rec-001/status \
   * -H "Content-Type: application/json" \
   * -d '{"status":"RECORDING"}'
   */
  @PutMapping("/{sessionId}/status")
  public ResponseEntity<?> updateStatus(@PathVariable String sessionId,
      @RequestBody UpdateStatusRequest request) {
    try {
      boolean updated = sessionService.updateSessionStatus(sessionId, request.getStatus());

      if (updated) {
        return ResponseEntity.ok(Map.of(
            "message", "Status updated",
            "sessionId", sessionId,
            "status", request.getStatus(),
            "timestamp", java.time.LocalDateTime.now()));
      } else {
        return ResponseEntity.notFound().build();
      }
    } catch (Exception e) {
      logger.error("Error updating session status: {}", e.getMessage(), e);
      return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
  }

  /**
   * Update recording path
   * PUT /api/sessions/{sessionId}/path
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! -X PUT \
   * http://localhost:8080/api/sessions/rec-001/path \
   * -H "Content-Type: application/json" \
   * -d '{"recordingPath":"/minio/recordings/rec-001.mp4"}'
   */
  @PutMapping("/{sessionId}/path")
  public ResponseEntity<?> updateRecordingPath(@PathVariable String sessionId,
      @RequestBody UpdatePathRequest request) {
    boolean updated = sessionService.updateRecordingPath(sessionId, request.getRecordingPath());

    if (updated) {
      return ResponseEntity.ok(Map.of(
          "message", "Recording path updated",
          "sessionId", sessionId,
          "recordingPath", request.getRecordingPath(),
          "timestamp", java.time.LocalDateTime.now()));
    } else {
      return ResponseEntity.notFound().build();
    }
  }

  /**
   * Stop a recording session
   * PUT /api/sessions/{sessionId}/stop
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! -X PUT
   * http://localhost:8080/api/sessions/rec-001/stop
   */
  @PutMapping("/{sessionId}/stop")
  public ResponseEntity<?> stopSession(@PathVariable String sessionId) {
    boolean stopped = sessionService.stopSession(sessionId);

    if (stopped) {
      return ResponseEntity.ok(Map.of(
          "message", "Session stopped",
          "sessionId", sessionId,
          "timestamp", java.time.LocalDateTime.now()));
    } else {
      return ResponseEntity.notFound().build();
    }
  }

  /**
   * Remove a session completely
   * DELETE /api/sessions/{sessionId}
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! -X DELETE
   * http://localhost:8080/api/sessions/rec-001
   */
  @DeleteMapping("/{sessionId}")
  public ResponseEntity<?> removeSession(@PathVariable String sessionId) {
    boolean removed = sessionService.removeSession(sessionId);

    if (removed) {
      return ResponseEntity.ok(Map.of(
          "message", "Session removed",
          "sessionId", sessionId,
          "timestamp", java.time.LocalDateTime.now()));
    } else {
      return ResponseEntity.notFound().build();
    }
  }

  /**
   * Check if session is active
   * GET /api/sessions/{sessionId}/active
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024!
   * http://localhost:8080/api/sessions/rec-001/active
   */
  @GetMapping("/{sessionId}/active")
  public ResponseEntity<Map<String, Object>> isSessionActive(@PathVariable String sessionId) {
    boolean active = sessionService.isSessionActive(sessionId);

    return ResponseEntity.ok(Map.of(
        "sessionId", sessionId,
        "active", active,
        "timestamp", java.time.LocalDateTime.now()));
  }

  /**
   * Manual cleanup of inactive sessions
   * POST /api/sessions/cleanup
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! -X POST
   * http://localhost:8080/api/sessions/cleanup
   */
  @PostMapping("/cleanup")
  public ResponseEntity<Map<String, Object>> manualCleanup() {
    int removedCount = sessionService.manualCleanup();

    return ResponseEntity.ok(Map.of(
        "message", "Manual cleanup completed",
        "removedSessions", removedCount,
        "timestamp", java.time.LocalDateTime.now()));
  }

  /**
   * Health check endpoint
   * GET /api/sessions/health
   * 
   * curl example:
   * curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health
   */
  @GetMapping("/health")
  public ResponseEntity<Map<String, Object>> health() {
    long activeCount = sessionService.getActiveSessionCount();

    return ResponseEntity.ok(Map.of(
        "status", "healthy",
        "activeSessions", activeCount,
        "timestamp", java.time.LocalDateTime.now(),
        "service", "recorder-ha-controller"));
  }

  // Helper method to get client IP address
  private String getClientIpAddress(HttpServletRequest request) {
    String xForwardedFor = request.getHeader("X-Forwarded-For");
    if (xForwardedFor != null && !xForwardedFor.isEmpty()) {
      return xForwardedFor.split(",")[0].trim();
    }

    String xRealIp = request.getHeader("X-Real-IP");
    if (xRealIp != null && !xRealIp.isEmpty()) {
      return xRealIp;
    }

    return request.getRemoteAddr();
  }

  // Request DTOs
  public static class CreateSessionRequest {
    private String sessionId;
    private String clientId;
    private String clientHost;
    private String metadata;

    // Getters and setters
    public String getSessionId() {
      return sessionId;
    }

    public void setSessionId(String sessionId) {
      this.sessionId = sessionId;
    }

    public String getClientId() {
      return clientId;
    }

    public void setClientId(String clientId) {
      this.clientId = clientId;
    }

    public String getClientHost() {
      return clientHost;
    }

    public void setClientHost(String clientHost) {
      this.clientHost = clientHost;
    }

    public String getMetadata() {
      return metadata;
    }

    public void setMetadata(String metadata) {
      this.metadata = metadata;
    }
  }

  public static class UpdateStatusRequest {
    private RecordingSession.SessionStatus status;

    public RecordingSession.SessionStatus getStatus() {
      return status;
    }

    public void setStatus(RecordingSession.SessionStatus status) {
      this.status = status;
    }
  }

  public static class UpdatePathRequest {
    private String recordingPath;

    public String getRecordingPath() {
      return recordingPath;
    }

    public void setRecordingPath(String recordingPath) {
      this.recordingPath = recordingPath;
    }
  }
}