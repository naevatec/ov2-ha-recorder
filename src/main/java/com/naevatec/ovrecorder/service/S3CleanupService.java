package com.naevatec.ovrecorder.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.net.URI;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Collectors;

@Service
@Slf4j
public class S3CleanupService {

    @Value("${app.aws.s3.bucket-name:}")
    private String bucketName;

    @Value("${app.aws.s3.access-key:}")
    private String accessKey;

    @Value("${app.aws.s3.secret-key:}")
    private String secretKey;

    @Value("${app.aws.s3.region:us-east-1}")
    private String region;

    @Value("${app.aws.s3.service-endpoint:}")
    private String serviceEndpoint;

    @Value("${app.recording.chunk.folder:chunks}")
    private String chunkFolder;

    @Value("${app.s3.cleanup.enabled:true}")
    private boolean cleanupEnabled;

    @Value("${app.s3.cleanup.async:true}")
    private boolean asyncCleanup;

    @Value("${app.s3.cleanup.batch-size:1000}")
    private int batchSize;

    private S3Client s3Client;
    private boolean s3Available = false;

    @PostConstruct
    public void initializeS3Client() {
        if (!cleanupEnabled) {
            log.info("🚫 S3 cleanup is disabled");
            return;
        }

        log.info("🔧 Starting S3 client initialization...");

        // Validate configuration
        if (!validateS3Configuration()) {
            return;
        }

        try {
            log.info("🔗 Initializing S3 client for cleanup operations...");
            log.info("   📍 Endpoint: {}", serviceEndpoint != null && !serviceEndpoint.trim().isEmpty() ? serviceEndpoint : "default AWS S3");
            log.info("   🪣 Bucket: {}", bucketName);
            log.info("   🌍 Region: {}", region);
            log.info("   🔑 Access Key: {}***", accessKey != null && accessKey.length() > 3 ? accessKey.substring(0, 3) : "null");

            AwsBasicCredentials credentials = AwsBasicCredentials.create(accessKey, secretKey);

            var clientBuilder = S3Client.builder()
                .credentialsProvider(StaticCredentialsProvider.create(credentials))
                .region(Region.of(region));

            // Use endpoint override for MinIO or custom S3-compatible services
            if (serviceEndpoint != null && !serviceEndpoint.trim().isEmpty()) {
                try {
                    URI endpointUri = URI.create(serviceEndpoint);
                    clientBuilder.endpointOverride(endpointUri);
                    log.info("🔗 Using custom S3 endpoint: {}", serviceEndpoint);
                } catch (Exception e) {
                    log.error("❌ Invalid S3 endpoint URL '{}': {}", serviceEndpoint, e.getMessage());
                    return;
                }
            }

            s3Client = clientBuilder.build();

            // Test S3 connectivity with detailed error handling
            testS3Connection();

            s3Available = true;
            log.info("✅ S3 cleanup service initialized successfully");

        } catch (Exception e) {
            log.error("❌ Failed to initialize S3 client: {}", e.getMessage(), e);
            s3Available = false;
        }
    }

    private boolean validateS3Configuration() {
        boolean valid = true;

        if (bucketName == null || bucketName.trim().isEmpty()) {
            log.warn("⚠️ S3 bucket name not configured (app.aws.s3.bucket-name), S3 cleanup disabled");
            valid = false;
        }

        if (accessKey == null || accessKey.trim().isEmpty()) {
            log.warn("⚠️ S3 access key not configured (app.aws.s3.access-key), S3 cleanup disabled");
            valid = false;
        }

        if (secretKey == null || secretKey.trim().isEmpty()) {
            log.warn("⚠️ S3 secret key not configured (app.aws.s3.secret-key), S3 cleanup disabled");
            valid = false;
        }

        return valid;
    }

    private void testS3Connection() {
        try {
            log.info("🔍 Testing S3 connection...");

            // First try a simple service check
            HeadBucketRequest headBucketRequest = HeadBucketRequest.builder()
                .bucket(bucketName)
                .build();

            s3Client.headBucket(headBucketRequest);
            log.info("✅ S3 bucket '{}' is accessible", bucketName);

        } catch (NoSuchBucketException e) {
            log.error("❌ S3 bucket '{}' does not exist", bucketName);
            log.info("💡 To create the bucket manually:");
            log.info("   docker-compose exec minio-mc mc mb local/{} --ignore-existing", bucketName);
            throw new RuntimeException("S3 bucket does not exist: " + bucketName, e);

        } catch (S3Exception e) {
            log.error("❌ S3 service error connecting to bucket '{}': {} (Status: {}, Code: {})",
                     bucketName, e.getMessage(), e.statusCode(), e.awsErrorDetails().errorCode());

            // Provide specific guidance for common errors
            if (e.statusCode() == 400) {
                log.error("💡 Status 400 usually indicates:");
                log.error("   - Incorrect endpoint URL format");
                log.error("   - Invalid credentials");
                log.error("   - MinIO service not ready");
                log.error("   - Network connectivity issues");

                // Additional debugging info
                log.error("🔍 Current configuration:");
                log.error("   - Endpoint: {}", serviceEndpoint);
                log.error("   - Bucket: {}", bucketName);
                log.error("   - Region: {}", region);
                log.error("   - Access Key: {}***", accessKey != null && accessKey.length() > 3 ? accessKey.substring(0, 3) : "null");
            }

            throw new RuntimeException("S3 connection test failed", e);

        } catch (SdkException e) {
            log.error("❌ AWS SDK error: {} ({})", e.getMessage(), e.getClass().getSimpleName());

            if (e.getMessage().contains("UnknownHostException")) {
                log.error("💡 Network issue: Cannot resolve hostname in endpoint URL");
                log.error("   - Check if MinIO service is running: docker-compose ps minio");
                log.error("   - Check endpoint URL: {}", serviceEndpoint);
            }

            throw new RuntimeException("S3 connection test failed", e);

        } catch (Exception e) {
            log.error("❌ Unexpected error during S3 connection test: {} ({})",
                     e.getMessage(), e.getClass().getSimpleName(), e);
            throw new RuntimeException("S3 connection test failed", e);
        }
    }

    /**
     * Clean up chunks for a session when it's removed (not deactivated)
     * Path pattern: ${bucket}/${sessionId}/${chunkFolder}/
     */
    public void cleanupSessionChunks(String sessionId) {
        if (!s3Available) {
            log.debug("S3 cleanup not available for session: {}", sessionId);
            return;
        }

        if (sessionId == null || sessionId.trim().isEmpty()) {
            log.warn("⚠️ Cannot cleanup chunks: sessionId is null or empty");
            return;
        }

        // Extract base session ID (before underscore)
        String baseSessionId = extractBaseSessionId(sessionId);
		// remove trailing slash if any from chunkFolder
		String chunkFolder = this.chunkFolder != null ? this.chunkFolder.replaceAll("/+$", "") : "chunks";
		// remove starting slash if any from chunkFolder
		chunkFolder = chunkFolder.replaceAll("^/+", "");
        String chunkPrefix = baseSessionId + "/" + chunkFolder + "/";

        log.info("🧹 Starting S3 chunk cleanup for session: {} (base: {})", sessionId, baseSessionId);
        log.debug("   - S3 Path: s3://{}/{}", bucketName, chunkPrefix);

        if (asyncCleanup) {
            // Async cleanup - don't block session removal
            CompletableFuture.runAsync(() -> performChunkCleanup(sessionId, baseSessionId, chunkPrefix))
                .exceptionally(throwable -> {
                    log.error("❌ Async S3 cleanup failed for session {}: {}", sessionId, throwable.getMessage(), throwable);
                    return null;
                });
        } else {
            // Synchronous cleanup
            performChunkCleanup(sessionId, baseSessionId, chunkPrefix);
        }
    }

    private void performChunkCleanup(String sessionId, String baseSessionId, String chunkPrefix) {
        try {
            log.debug("🔍 Listing objects in s3://{}/{}", bucketName, chunkPrefix);

            // List all objects with the chunk prefix
            ListObjectsV2Request listRequest = ListObjectsV2Request.builder()
                .bucket(bucketName)
                .prefix(chunkPrefix)
                .maxKeys(batchSize)
                .build();

            ListObjectsV2Response listResponse;
            int totalObjectsDeleted = 0;
            int batchCount = 0;

            do {
                listResponse = s3Client.listObjectsV2(listRequest);
                List<S3Object> objects = listResponse.contents();

                if (objects.isEmpty()) {
                    if (batchCount == 0) {
                        log.info("🔭 No chunks found for session {} at s3://{}/{}",
                                sessionId, bucketName, chunkPrefix);
                    }
                    break;
                }

                batchCount++;
                log.debug("📦 Batch {}: Found {} objects to delete", batchCount, objects.size());

                // Prepare batch delete request
                List<ObjectIdentifier> objectsToDelete = objects.stream()
                    .map(s3Object -> ObjectIdentifier.builder()
                        .key(s3Object.key())
                        .build())
                    .collect(Collectors.toList());

                Delete delete = Delete.builder()
                    .objects(objectsToDelete)
                    .quiet(false)  // Get detailed response
                    .build();

                DeleteObjectsRequest deleteRequest = DeleteObjectsRequest.builder()
                    .bucket(bucketName)
                    .delete(delete)
                    .build();

                // Execute batch delete
                DeleteObjectsResponse deleteResponse = s3Client.deleteObjects(deleteRequest);

                int deletedCount = deleteResponse.deleted().size();
                totalObjectsDeleted += deletedCount;

                log.debug("🗑️ Batch {}: Deleted {} objects", batchCount, deletedCount);

                // Log any errors
                if (!deleteResponse.errors().isEmpty()) {
                    deleteResponse.errors().forEach(error ->
                        log.warn("⚠️ Failed to delete object {}: {} ({})",
                                error.key(), error.message(), error.code()));
                }

                // Continue with next batch if truncated
                listRequest = listRequest.toBuilder()
                    .continuationToken(listResponse.nextContinuationToken())
                    .build();

            } while (listResponse.isTruncated());

            if (totalObjectsDeleted > 0) {
                log.info("✅ S3 cleanup completed for session {}: {} objects deleted in {} batches",
                        sessionId, totalObjectsDeleted, batchCount);
            } else {
                log.debug("🔭 No chunks found to cleanup for session {}", sessionId);
            }

            // Optionally clean up empty directories (attempt to delete the folder itself)
            tryCleanupEmptyDirectory(baseSessionId, chunkPrefix);

        } catch (SdkException e) {
            log.error("❌ S3 cleanup failed for session {}: {} ({})",
                    sessionId, e.getMessage(), e.getClass().getSimpleName(), e);
        } catch (Exception e) {
            log.error("❌ Unexpected error during S3 cleanup for session {}: {}",
                    sessionId, e.getMessage(), e);
        }
    }

    private void tryCleanupEmptyDirectory(String baseSessionId, String chunkPrefix) {
        try {
            // Try to delete the chunk directory marker (if it exists)
            String directoryMarker = chunkPrefix; // Some S3 implementations create directory markers

            HeadObjectRequest headRequest = HeadObjectRequest.builder()
                .bucket(bucketName)
                .key(directoryMarker)
                .build();

            try {
                s3Client.headObject(headRequest);

                // Directory marker exists, try to delete it
                DeleteObjectRequest deleteRequest = DeleteObjectRequest.builder()
                    .bucket(bucketName)
                    .key(directoryMarker)
                    .build();

                s3Client.deleteObject(deleteRequest);
                log.debug("🗂️ Cleaned up directory marker: s3://{}/{}", bucketName, directoryMarker);

            } catch (NoSuchKeyException e) {
                // Directory marker doesn't exist, that's fine
                log.debug("🔍 No directory marker to cleanup for: s3://{}/{}", bucketName, directoryMarker);
            }

        } catch (Exception e) {
            log.debug("⚠️ Could not cleanup directory for session {}: {}", baseSessionId, e.getMessage());
            // This is not critical, so we don't log it as an error
        }
    }

    /**
     * Extract base session ID (part before underscore)
     * Example: "session123_456789" -> "session123"
     */
    private String extractBaseSessionId(String sessionId) {
        if (sessionId == null) {
            return "";
        }

        int underscoreIndex = sessionId.indexOf('_');
        if (underscoreIndex > 0) {
            return sessionId.substring(0, underscoreIndex);
        }

        return sessionId; // No underscore found, return as-is
    }

    /**
     * Check if S3 cleanup is available and configured
     */
    public boolean isS3CleanupAvailable() {
        return s3Available && cleanupEnabled;
    }

    /**
     * Get S3 cleanup configuration info
     */
    public String getS3CleanupInfo() {
        if (!cleanupEnabled) {
            return "S3 cleanup is disabled";
        }

        if (!s3Available) {
            return "S3 cleanup is not available (configuration or connection error)";
        }

        return String.format("S3 cleanup enabled - Bucket: %s, Endpoint: %s, Async: %s",
                           bucketName,
                           serviceEndpoint != null && !serviceEndpoint.trim().isEmpty() ? serviceEndpoint : "default AWS S3",
                           asyncCleanup);
    }

    @PreDestroy
    public void cleanup() {
        if (s3Client != null) {
            try {
                s3Client.close();
                log.info("🔒 S3 client closed successfully");
            } catch (Exception e) {
                log.warn("⚠️ Error closing S3 client: {}", e.getMessage());
            }
        }
    }
}
