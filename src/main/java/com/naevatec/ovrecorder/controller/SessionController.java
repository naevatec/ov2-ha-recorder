package com.naevatec.ovrecorder.controller;

import com.naevatec.ovrecorder.model.RecordingSession;
import com.naevatec.ovrecorder.service.SessionService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
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
@Tag(name = "Recording Sessions", description = "API for managing video recording sessions in HA environment")
@SecurityRequirement(name = "basicAuth")
public class SessionController {

  private static final Logger logger = LoggerFactory.getLogger(SessionController.class);

  private final SessionService sessionService;

  public SessionController(SessionService sessionService) {
    this.sessionService = sessionService;
  }

  @Operation(
      summary = "Create a new recording session",
      description = "Creates a new recording session with the provided session ID, client ID, and optional client host. " +
                   "If client host is not provided, it will be extracted from the request headers."
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "201", description = "Session created successfully",
          content = @Content(schema = @Schema(implementation = RecordingSession.class))),
      @ApiResponse(responseCode = "400", description = "Invalid request data or session already exists",
          content = @Content(schema = @Schema(implementation = Map.class))),
      @ApiResponse(responseCode = "500", description = "Internal server error",
          content = @Content(schema = @Schema(implementation = Map.class)))
  })
  @PostMapping
  public ResponseEntity<?> createSession(
      @io.swagger.v3.oas.annotations.parameters.RequestBody(
          description = "Session creation request data",
          required = true,
          content = @Content(
              schema = @Schema(implementation = CreateSessionRequest.class),
              examples = @ExampleObject(
                  name = "Example Session Creation",
                  value = """
                  {
                    "sessionId": "112_-_eiglesia_emer_minusculas_-_27541_-_2_-_e7f0bc2500695967644cc47135eb105f",
                    "clientId": "client-01",
                    "clientHost": "192.168.1.100",
                    "metadata": "Optional metadata for the session"
                  }
                  """
              )
          )
      )
      @Valid @RequestBody CreateSessionRequest request,
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

  @Operation(
      summary = "Get session by ID",
      description = "Retrieves a specific recording session by its session ID"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Session found",
          content = @Content(schema = @Schema(implementation = RecordingSession.class))),
      @ApiResponse(responseCode = "404", description = "Session not found")
  })
  @GetMapping("/{sessionId}")
  public ResponseEntity<?> getSession(
      @Parameter(description = "Unique identifier of the recording session", example = "rec-001")
      @PathVariable String sessionId) {
    Optional<RecordingSession> session = sessionService.getSession(sessionId);

    if (session.isPresent()) {
      return ResponseEntity.ok(session.get());
    } else {
      return ResponseEntity.notFound().build();
    }
  }

  @Operation(
      summary = "Get all active sessions",
      description = "Retrieves a list of all currently active recording sessions with their count and timestamp"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Sessions retrieved successfully",
          content = @Content(
              schema = @Schema(implementation = Map.class),
              examples = @ExampleObject(
                  name = "Sessions Response",
                  value = """
                  {
                    "sessions": [...],
                    "count": 3,
                    "timestamp": "2024-01-20T10:30:00"
                  }
                  """
              )
          ))
  })
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

  @Operation(
      summary = "Update session heartbeat",
      description = "Updates the heartbeat timestamp for a session to indicate it's still active. " +
                   "This is used for session health monitoring and automatic cleanup."
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Heartbeat updated successfully"),
      @ApiResponse(responseCode = "404", description = "Session not found")
  })
  @PutMapping("/{sessionId}/heartbeat")
  public ResponseEntity<?> updateHeartbeat(
      @Parameter(description = "Unique identifier of the recording session", example = "rec-001")
      @PathVariable String sessionId) {
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

  @Operation(
      summary = "Update session status",
      description = "Updates the status of a recording session (STARTING, RECORDING, PAUSED, STOPPING, COMPLETED, FAILED, INACTIVE)"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Status updated successfully"),
      @ApiResponse(responseCode = "400", description = "Invalid status value"),
      @ApiResponse(responseCode = "404", description = "Session not found")
  })
  @PutMapping("/{sessionId}/status")
  public ResponseEntity<?> updateStatus(
      @Parameter(description = "Unique identifier of the recording session", example = "rec-001")
      @PathVariable String sessionId,
      @io.swagger.v3.oas.annotations.parameters.RequestBody(
          description = "Status update request",
          content = @Content(
              schema = @Schema(implementation = UpdateStatusRequest.class),
              examples = @ExampleObject(
                  value = """
                  {
                    "status": "RECORDING"
                  }
                  """
              )
          )
      )
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

  @Operation(
      summary = "Update recording path",
      description = "Updates the file path where the recording is being stored"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Recording path updated successfully"),
      @ApiResponse(responseCode = "404", description = "Session not found")
  })
  @PutMapping("/{sessionId}/path")
  public ResponseEntity<?> updateRecordingPath(
      @Parameter(description = "Unique identifier of the recording session", example = "rec-001")
      @PathVariable String sessionId,
      @io.swagger.v3.oas.annotations.parameters.RequestBody(
          description = "Recording path update request",
          content = @Content(
              schema = @Schema(implementation = UpdatePathRequest.class),
              examples = @ExampleObject(
                  value = """
                  {
                    "recordingPath": "/minio/recordings/rec-001.mp4"
                  }
                  """
              )
          )
      )
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

  @Operation(
      summary = "Stop a recording session",
      description = "Stops an active recording session by changing its status to STOPPING and then COMPLETED"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Session stopped successfully"),
      @ApiResponse(responseCode = "404", description = "Session not found")
  })
  @PutMapping("/{sessionId}/stop")
  public ResponseEntity<?> stopSession(
      @Parameter(description = "Unique identifier of the recording session", example = "rec-001")
      @PathVariable String sessionId) {
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

  @Operation(
      summary = "Remove a session completely",
      description = "Permanently removes a recording session from Redis. Use with caution!"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Session removed successfully"),
      @ApiResponse(responseCode = "404", description = "Session not found")
  })
  @DeleteMapping("/{sessionId}")
  public ResponseEntity<?> removeSession(
      @Parameter(description = "Unique identifier of the recording session", example = "rec-001")
      @PathVariable String sessionId) {
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

  @Operation(
      summary = "Check if session is active",
      description = "Checks whether a specific session is currently active (RECORDING or STARTING status)"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Session status checked successfully")
  })
  @GetMapping("/{sessionId}/active")
  public ResponseEntity<Map<String, Object>> isSessionActive(
      @Parameter(description = "Unique identifier of the recording session", example = "rec-001")
      @PathVariable String sessionId) {
    boolean active = sessionService.isSessionActive(sessionId);

    return ResponseEntity.ok(Map.of(
        "sessionId", sessionId,
        "active", active,
        "timestamp", java.time.LocalDateTime.now()));
  }

  @Operation(
      summary = "Manual cleanup of inactive sessions",
      description = "Manually triggers cleanup of sessions that haven't sent heartbeats within the configured timeout period"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Cleanup completed successfully")
  })
  @PostMapping("/cleanup")
  public ResponseEntity<Map<String, Object>> manualCleanup() {
    int removedCount = sessionService.manualCleanup();

    return ResponseEntity.ok(Map.of(
        "message", "Manual cleanup completed",
        "removedSessions", removedCount,
        "timestamp", java.time.LocalDateTime.now()));
  }

  @Operation(
      summary = "Health check endpoint",
      description = "Returns the health status of the session controller and count of active sessions"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Service is healthy")
  })
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

  // Request DTOs with Swagger documentation
  @Schema(description = "Request object for creating a new recording session")
  public static class CreateSessionRequest {
    @Schema(description = "Unique identifier for the recording session",
            example = "112_-_eiglesia_emer_minusculas_-_27541_-_2_-_e7f0bc2500695967644cc47135eb105f",
            required = true)
    private String sessionId;

    @Schema(description = "Identifier of the client creating the session",
            example = "client-01",
            required = true)
    private String clientId;

    @Schema(description = "IP address or hostname of the client (optional, will be auto-detected if not provided)",
            example = "192.168.1.100")
    private String clientHost;

    @Schema(description = "Optional metadata for the session",
            example = "Recording metadata or additional info")
    private String metadata;

    // Getters and setters
    public String getSessionId() { return sessionId; }
    public void setSessionId(String sessionId) { this.sessionId = sessionId; }
    public String getClientId() { return clientId; }
    public void setClientId(String clientId) { this.clientId = clientId; }
    public String getClientHost() { return clientHost; }
    public void setClientHost(String clientHost) { this.clientHost = clientHost; }
    public String getMetadata() { return metadata; }
    public void setMetadata(String metadata) { this.metadata = metadata; }
  }

  @Schema(description = "Request object for updating session status")
  public static class UpdateStatusRequest {
    @Schema(description = "New status for the session",
            example = "RECORDING",
            allowableValues = {"STARTING", "RECORDING", "PAUSED", "STOPPING", "COMPLETED", "FAILED", "INACTIVE"})
    private RecordingSession.SessionStatus status;

    public RecordingSession.SessionStatus getStatus() { return status; }
    public void setStatus(RecordingSession.SessionStatus status) { this.status = status; }
  }

  @Schema(description = "Request object for updating recording file path")
  public static class UpdatePathRequest {
    @Schema(description = "File path where the recording is stored",
            example = "/minio/recordings/rec-001.mp4")
    private String recordingPath;

    public String getRecordingPath() { return recordingPath; }
    public void setRecordingPath(String recordingPath) { this.recordingPath = recordingPath; }
  }
}
