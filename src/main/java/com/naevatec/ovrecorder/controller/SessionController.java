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
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/sessions")
@Tag(name = "Recording Sessions", description = "Simplified API for managing recording sessions in HA environment")
@SecurityRequirement(name = "basicAuth")
@RequiredArgsConstructor
@Slf4j
public class SessionController {

  private final SessionService sessionService;

  /**
   * Create a new recording session
   * POST /api/sessions
   */
  @Operation(
      summary = "Create a new recording session",
      description = "Creates a new recording session with the provided session ID, client ID, and optional client host."
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
  public ResponseEntity<?> createSession(@Valid @RequestBody CreateSessionRequest request,
      HttpServletRequest httpRequest) {
    try {
      String clientHost = request.getClientHost() != null ? request.getClientHost() : getClientIpAddress(httpRequest);

      RecordingSession session = sessionService.createSession(
          request.getSessionId(),
          request.getClientId(),
          clientHost);

      log.info("Created session via API: {} from {}", session.getSessionId(), clientHost);
      return ResponseEntity.status(HttpStatus.CREATED).body(session);

    } catch (IllegalArgumentException e) {
      log.warn("Failed to create session: {}", e.getMessage());
      return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    } catch (Exception e) {
      log.error("Error creating session: {}", e.getMessage(), e);
      return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
          .body(Map.of("error", "Internal server error"));
    }
  }

  /**
   * Get session by ID
   * GET /api/sessions/{sessionId}
   */
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

  /**
   * Get all active sessions
   * GET /api/sessions
   */
  @Operation(
      summary = "Get all active sessions",
      description = "Retrieves a list of all currently active recording sessions with their count and timestamp"
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Sessions retrieved successfully")
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

  /**
   * Update session heartbeat with optional chunk information
   * PUT /api/sessions/{sessionId}/heartbeat
   */
  @Operation(
      summary = "Update session heartbeat",
      description = "Updates the heartbeat timestamp for a session with optional chunk information for monitoring."
  )
  @ApiResponses(value = {
      @ApiResponse(responseCode = "200", description = "Heartbeat updated successfully"),
      @ApiResponse(responseCode = "404", description = "Session not found")
  })
  @PutMapping("/{sessionId}/heartbeat")
  public ResponseEntity<?> updateHeartbeat(
      @Parameter(description = "Unique identifier of the recording session", example = "rec-001")
      @PathVariable String sessionId,
      @io.swagger.v3.oas.annotations.parameters.RequestBody(
          description = "Heartbeat update request with optional chunk information",
          content = @Content(
              schema = @Schema(implementation = HeartbeatRequest.class),
              examples = @ExampleObject(
                  value = """
                  {
                    "lastChunk": "0001.mp4"
                  }
                  """
              )
          )
      )
      @RequestBody(required = false) HeartbeatRequest request) {

    String lastChunk = null;
    if (request != null && request.getLastChunk() != null) {
      lastChunk = request.getLastChunk();
    }

    boolean updated = sessionService.updateHeartbeat(sessionId, lastChunk);

    if (updated) {
      Map<String, Object> response = new HashMap<>();
      response.put("message", "Heartbeat updated");
      response.put("sessionId", sessionId);
      response.put("timestamp", java.time.LocalDateTime.now());

      if (lastChunk != null) {
        response.put("lastChunk", lastChunk);
      }

      return ResponseEntity.ok(response);
    } else {
      return ResponseEntity.notFound().build();
    }
  }

  /**
   * Remove a session completely (deregistration)
   * DELETE /api/sessions/{sessionId}
   */
  @Operation(
      summary = "Remove a session completely",
      description = "Permanently removes a recording session from the HA Controller (deregistration)."
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

  /**
   * Check if session is active
   * GET /api/sessions/{sessionId}/active
   */
  @Operation(
      summary = "Check if session is active",
      description = "Checks whether a specific session is currently active"
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

  /**
   * Manual cleanup of inactive sessions
   * POST /api/sessions/cleanup
   */
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

  /**
   * Health check endpoint
   * GET /api/sessions/health
   */
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

  // Request DTOs with Lombok
  @Schema(description = "Request object for creating a new recording session")
  @lombok.Data
  public static class CreateSessionRequest {
    @Schema(description = "Unique identifier for the recording session",
            example = "112_-_eiglesia_emer_minusculas_-_27541_-_2_-_e7f0bc2500695967644cc47135eb105f")
    private String sessionId;

    @Schema(description = "Identifier of the client creating the session",
            example = "client-01")
    private String clientId;

    @Schema(description = "IP address or hostname of the client (optional, will be auto-detected if not provided)",
            example = "192.168.1.100")
    private String clientHost;

    @Schema(description = "Optional metadata for the session",
            example = "Recording metadata or additional info")
    private String metadata;
  }

  @Schema(description = "Request object for heartbeat updates")
  @lombok.Data
  public static class HeartbeatRequest {
    @Schema(description = "Name of the last chunk file created",
            example = "0001.mp4")
    private String lastChunk;
  }
}
