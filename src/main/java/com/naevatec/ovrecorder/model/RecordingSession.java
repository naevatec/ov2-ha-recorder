package com.naevatec.ovrecorder.model;

import java.time.LocalDateTime;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonProperty;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.ToString;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@ToString(exclude = {"metadata"}) // Exclude metadata from toString to avoid log pollution
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
  @Builder.Default
  private SessionStatus status = SessionStatus.STARTING;

  @JsonProperty("createdAt")
  @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
  @Builder.Default
  private LocalDateTime createdAt = LocalDateTime.now();

  @JsonProperty("lastHeartbeat")
  @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
  @Builder.Default
  private LocalDateTime lastHeartbeat = LocalDateTime.now();

  @JsonProperty("recordingPath")
  private String recordingPath;

  @JsonProperty("metadata")
  private String metadata;

  @JsonProperty("lastChunk")
  private String lastChunk;

  @JsonProperty("active")
  @Builder.Default
  private Boolean active = true;

  @JsonProperty("backupContainerId")
  private String backupContainerId;

  @JsonProperty("backupContainerName")
  private String backupContainerName;

  // Custom constructor for backward compatibility
  public RecordingSession(String sessionId, String clientId, String clientHost) {
    this.sessionId = sessionId;
    this.clientId = clientId;
    this.clientHost = clientHost;
    this.status = SessionStatus.STARTING;
    this.createdAt = LocalDateTime.now();
    this.lastHeartbeat = LocalDateTime.now();
    this.active = true;
  }

  // Utility methods
  public void updateHeartbeat() {
    this.lastHeartbeat = LocalDateTime.now();
  }

  public void updateHeartbeat(String lastChunk) {
    this.lastHeartbeat = LocalDateTime.now();
    this.lastChunk = lastChunk;
  }

  public boolean isActive() {
    // Check both the active flag and status
    return Boolean.TRUE.equals(active) &&
           (status == SessionStatus.RECORDING || status == SessionStatus.STARTING);
  }

  public boolean isInactive(long maxInactiveSeconds) {
    if (lastHeartbeat == null) {
      return true;
    }
    return lastHeartbeat.isBefore(LocalDateTime.now().minusSeconds(maxInactiveSeconds));
  }

  public void markAsInactive() {
    this.active = false;
    this.status = SessionStatus.INACTIVE;
  }

  public void markAsActive() {
    this.active = true;
    if (this.status == SessionStatus.INACTIVE) {
      this.status = SessionStatus.STARTING;
    }
  }

  // Custom equals and hashCode based only on sessionId (Lombok @Data provides default implementation)
  @Override
  public boolean equals(Object o) {
    if (this == o) return true;
    if (o == null || getClass() != o.getClass()) return false;
    RecordingSession that = (RecordingSession) o;
    return sessionId != null ? sessionId.equals(that.sessionId) : that.sessionId == null;
  }

  @Override
  public int hashCode() {
    return sessionId != null ? sessionId.hashCode() : 0;
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
