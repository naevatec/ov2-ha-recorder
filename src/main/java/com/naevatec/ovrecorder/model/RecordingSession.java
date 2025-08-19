package com.naevatec.ovrecorder.model;

import java.time.LocalDateTime;
import java.util.Objects;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonProperty;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public class RecordingSession {

  @NotBlank(message = "Session ID cannot be blank")
  @JsonProperty("sessionId")
  private String sessionId;

  @NotBlank(message = "Client ID cannot be blank")
  @JsonProperty("clientId")
  private String clientId;

  @JsonProperty("clientHost")
  private String clientHost;

  @NotNull(message = "Status cannot be null")
  @JsonProperty("status")
  private SessionStatus status;

  @JsonProperty("createdAt")
  @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
  private LocalDateTime createdAt;

  @JsonProperty("lastHeartbeat")
  @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
  private LocalDateTime lastHeartbeat;

  @JsonProperty("recordingPath")
  private String recordingPath;

  @JsonProperty("metadata")
  private String metadata;

  // Constructors
  public RecordingSession() {
    this.createdAt = LocalDateTime.now();
    this.lastHeartbeat = LocalDateTime.now();
    this.status = SessionStatus.STARTING;
  }

  public RecordingSession(String sessionId, String clientId, String clientHost) {
    this();
    this.sessionId = sessionId;
    this.clientId = clientId;
    this.clientHost = clientHost;
  }

  // Getters and Setters
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

  public SessionStatus getStatus() {
    return status;
  }

  public void setStatus(SessionStatus status) {
    this.status = status;
  }

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  public void setCreatedAt(LocalDateTime createdAt) {
    this.createdAt = createdAt;
  }

  public LocalDateTime getLastHeartbeat() {
    return lastHeartbeat;
  }

  public void setLastHeartbeat(LocalDateTime lastHeartbeat) {
    this.lastHeartbeat = lastHeartbeat;
  }

  public String getRecordingPath() {
    return recordingPath;
  }

  public void setRecordingPath(String recordingPath) {
    this.recordingPath = recordingPath;
  }

  public String getMetadata() {
    return metadata;
  }

  public void setMetadata(String metadata) {
    this.metadata = metadata;
  }

  // Utility methods
  public void updateHeartbeat() {
    this.lastHeartbeat = LocalDateTime.now();
  }

  public boolean isActive() {
    return status == SessionStatus.RECORDING || status == SessionStatus.STARTING;
  }

  public boolean isInactive(long maxInactiveSeconds) {
    if (lastHeartbeat == null) {
      return true;
    }
    return lastHeartbeat.isBefore(LocalDateTime.now().minusSeconds(maxInactiveSeconds));
  }

  @Override
  public boolean equals(Object o) {
    if (this == o)
      return true;
    if (o == null || getClass() != o.getClass())
      return false;
    RecordingSession that = (RecordingSession) o;
    return Objects.equals(sessionId, that.sessionId);
  }

  @Override
  public int hashCode() {
    return Objects.hash(sessionId);
  }

  @Override
  public String toString() {
    return "RecordingSession{" +
        "sessionId='" + sessionId + '\'' +
        ", clientId='" + clientId + '\'' +
        ", clientHost='" + clientHost + '\'' +
        ", status=" + status +
        ", createdAt=" + createdAt +
        ", lastHeartbeat=" + lastHeartbeat +
        ", recordingPath='" + recordingPath + '\'' +
        '}';
  }

  // Session Status Enum
  public enum SessionStatus {
    STARTING,
    RECORDING,
    PAUSED,
    STOPPING,
    COMPLETED,
    FAILED,
    INACTIVE
  }
}