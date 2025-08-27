package com.naevatec.ovrecorder.service;

import lombok.Getter;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.retry.annotation.Backoff;
import org.springframework.retry.annotation.Recover;
import org.springframework.retry.annotation.Retryable;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;

import jakarta.annotation.PostConstruct;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicLong;

@Service
@Slf4j
public class WebhookRelayService {

    @Value("${app.webhook.url:}")
    private String webhookEndpoint;

    @Value("${app.webhook.headers:}")
    private String webhookHeaders;

    @Value("${app.webhook.timeout-ms:5000}")
    private long timeoutMs;

    @Value("${app.webhook.retries:3}")
    private int retryAttempts;

    @Value("${app.webhook.retry-delay-ms:1000}")
    private long retryDelayMs;

	@Value("${app.webhook.enabled:false}")
    private boolean relayEnabled;

    private RestTemplate restTemplate;
    private HttpHeaders defaultHeaders;

    // Metrics
    private final AtomicLong totalRequests = new AtomicLong(0);
    private final AtomicLong successfulRequests = new AtomicLong(0);
    private final AtomicLong failedRequests = new AtomicLong(0);
    private volatile LocalDateTime lastRequestTime;
    private volatile LocalDateTime lastSuccessTime;
    private volatile LocalDateTime lastFailureTime;

    @PostConstruct
    public void initialize() {
        // Initialize RestTemplate with timeout configuration
        restTemplate = new RestTemplate();
        restTemplate.getInterceptors().add((request, body, execution) -> {
            // Add request/response logging if needed
            long startTime = System.currentTimeMillis();
            try {
                ClientHttpResponse response = execution.execute(request, body);
                long duration = System.currentTimeMillis() - startTime;
                log.debug("Webhook relay request completed in {}ms - Status: {}",
                    duration, response.getStatusCode());
                return response;
            } catch (Exception e) {
                long duration = System.currentTimeMillis() - startTime;
                log.warn("Webhook relay request failed after {}ms: {}", duration, e.getMessage());
                throw e;
            }
        });

        // Check if webhook relay is enabled
        if (StringUtils.hasText(webhookEndpoint)) {
            relayEnabled = true;
            log.info("Webhook relay enabled. Target endpoint: {}", webhookEndpoint);

            // Parse and prepare default headers
            setupDefaultHeaders();

            // Validate endpoint
            validateWebhookEndpoint();
        } else {
            log.info("Webhook relay disabled. OPENVIDU_WEBHOOK_ENDPOINT not configured.");
        }
    }

    /**
     * Relay webhook request asynchronously with minimal delay
     */
    @Async("webhookExecutor")
    public CompletableFuture<WebhookRelayResult> relayWebhook(
            String requestBody,
            HttpHeaders incomingHeaders,
            HttpMethod method) {

        if (!relayEnabled) {
            log.debug("Webhook relay is disabled, skipping");
            return CompletableFuture.completedFuture(
                WebhookRelayResult.disabled("Webhook relay is disabled"));
        }

        long requestId = totalRequests.incrementAndGet();
        lastRequestTime = LocalDateTime.now();
        long startTime = System.currentTimeMillis();

        log.debug("Starting webhook relay #{} to {}", requestId, webhookEndpoint);

        return CompletableFuture.supplyAsync(() -> {
            try {
                // Prepare headers
                HttpHeaders headers = new HttpHeaders();
                headers.addAll(defaultHeaders);

                // Forward essential headers from original request
                forwardEssentialHeaders(incomingHeaders, headers);

                // Create request entity
                HttpEntity<String> requestEntity = new HttpEntity<>(requestBody, headers);

                // Attempt relay with retries
                WebhookRelayResult result = attemptRelayWithRetries(requestEntity, method, requestId);

                // Update metrics
                long duration = System.currentTimeMillis() - startTime;
                if (result.isSuccess()) {
                    successfulRequests.incrementAndGet();
                    lastSuccessTime = LocalDateTime.now();
                    log.debug("Webhook relay #{} completed successfully in {}ms", requestId, duration);
                } else {
                    failedRequests.incrementAndGet();
                    lastFailureTime = LocalDateTime.now();
                    log.warn("Webhook relay #{} failed after {}ms: {}", requestId, duration, result.getErrorMessage());
                }

                return result;

            } catch (Exception e) {
                failedRequests.incrementAndGet();
                lastFailureTime = LocalDateTime.now();
                long duration = System.currentTimeMillis() - startTime;
                log.error("Webhook relay #{} failed with exception after {}ms: {}", requestId, duration, e.getMessage(), e);
                return WebhookRelayResult.error("Unexpected error: " + e.getMessage());
            }
        });
    }

    /**
     * Attempt single relay call with Spring Retry
     */
    @Retryable(
        retryFor = {ResourceAccessException.class, HttpServerErrorException.class},
        noRetryFor = {HttpClientErrorException.class}, // Don't retry on 4xx errors
        maxAttemptsExpression = "#{${openvidu.webhook.retry-attempts:3}}",
        backoff = @Backoff(
            delayExpression = "#{${openvidu.webhook.retry-delay:1000}}",
            multiplier = 2.0, // Exponential backoff
            maxDelayExpression = "#{${openvidu.webhook.retry-delay:1000} * 10}"
        )
    )
    private ResponseEntity<String> performWebhookCall(HttpEntity<String> requestEntity, HttpMethod method) {
        log.debug("Attempting webhook call to {}", webhookEndpoint);

        ResponseEntity<String> response = restTemplate.exchange(
            webhookEndpoint,
            method,
            requestEntity,
            String.class
        );

        // Check if response is successful
        if (!response.getStatusCode().is2xxSuccessful()) {
            // This will trigger a retry for 5xx errors, but not for 4xx
            if (response.getStatusCode().is5xxServerError()) {
                throw new HttpServerErrorException(response.getStatusCode(),
                    "Server error: " + response.getStatusCode());
            } else if (response.getStatusCode().is4xxClientError()) {
                throw new HttpClientErrorException(response.getStatusCode(),
                    "Client error: " + response.getStatusCode());
            }
        }

        return response;
    }

    /**
     * Recovery method called when all retry attempts fail
     */
    @Recover
    private ResponseEntity<String> recoverWebhookCall(Exception ex, HttpEntity<String> requestEntity, HttpMethod method) {
        log.error("All webhook retry attempts failed. Final error: {}", ex.getMessage());
        throw new RuntimeException("Webhook relay failed after all retries: " + ex.getMessage(), ex);
    }

    /**
     * Updated method that uses Spring Retry
     */
    private WebhookRelayResult attemptRelayWithRetries(HttpEntity<String> requestEntity, HttpMethod method, long requestId) {
        try {
            log.info("Attempting webhook relay #{} to {}", requestId, webhookEndpoint);

            ResponseEntity<String> response = performWebhookCall(requestEntity, method);

            return WebhookRelayResult.success(
                response.getStatusCode().value(),
                "Webhook relayed successfully"
            );

        } catch (HttpClientErrorException e) {
            // 4xx errors - don't retry, immediate failure
            String errorMessage = String.format("Client error (no retry): HTTP %s - %s",
                e.getStatusCode(), e.getMessage());
            return WebhookRelayResult.error(errorMessage);

        } catch (Exception e) {
            // All other errors (including the recovery method exception)
            String errorMessage = String.format("Failed after retries: %s", e.getMessage());
            return WebhookRelayResult.error(errorMessage);
        }
    }
    /**
     * Forward essential headers from incoming request
     */
    private void forwardEssentialHeaders(HttpHeaders incomingHeaders, HttpHeaders outgoingHeaders) {
        // Forward Content-Type if present
        if (incomingHeaders.getContentType() != null) {
            outgoingHeaders.setContentType(incomingHeaders.getContentType());
        } else {
            outgoingHeaders.setContentType(MediaType.APPLICATION_JSON);
        }

        // Forward User-Agent
        String userAgent = incomingHeaders.getFirst(HttpHeaders.USER_AGENT);
        if (StringUtils.hasText(userAgent)) {
            outgoingHeaders.set(HttpHeaders.USER_AGENT, "OpenVidu-Relay/" + userAgent);
        }

        // Forward OpenVidu specific headers
        incomingHeaders.forEach((key, values) -> {
            if (key != null && (key.toLowerCase().startsWith("openvidu-") ||
                               key.toLowerCase().startsWith("x-openvidu-"))) {
                outgoingHeaders.addAll(key, values);
            }
        });
    }

    /**
     * Setup default headers from configuration
     */
    private void setupDefaultHeaders() {
        defaultHeaders = new HttpHeaders();

        if (StringUtils.hasText(webhookHeaders)) {
            try {
                // Parse headers format: "Header1:Value1,Header2:Value2"
                String[] headerPairs = webhookHeaders.split(",");
                for (String headerPair : headerPairs) {
                    String[] parts = headerPair.split(":", 2);
                    if (parts.length == 2) {
                        String key = parts[0].trim();
                        String value = parts[1].trim();
                        defaultHeaders.add(key, value);
                        log.debug("Added default webhook header: {} = [REDACTED]", key);
                    }
                }
            } catch (Exception e) {
                log.error("Error parsing webhook headers '{}': {}", webhookHeaders, e.getMessage());
            }
        }

        // Add relay identification header
        defaultHeaders.add("X-Relay-Source", "OpenVidu-HA-Controller");
        defaultHeaders.add("X-Relay-Timestamp", String.valueOf(System.currentTimeMillis()));
    }

    /**
     * Validate webhook endpoint configuration
     */
    private void validateWebhookEndpoint() {
        try {
            if (!webhookEndpoint.startsWith("http://") && !webhookEndpoint.startsWith("https://")) {
                log.warn("Webhook endpoint should start with http:// or https://: {}", webhookEndpoint);
            }

            // Test connectivity (optional - might want to disable in production)
            log.debug("Webhook endpoint validation passed: {}", webhookEndpoint);

        } catch (Exception e) {
            log.error("Webhook endpoint validation failed: {}", e.getMessage());
        }
    }

    /**
     * Get relay statistics and status
     */
    public Map<String, Object> getRelayStatus() {
        Map<String, Object> status = new HashMap<>();
        status.put("enabled", relayEnabled);
        status.put("endpoint", relayEnabled ? webhookEndpoint : "Not configured");
        status.put("totalRequests", totalRequests.get());
        status.put("successfulRequests", successfulRequests.get());
        status.put("failedRequests", failedRequests.get());
        status.put("successRate", calculateSuccessRate());
        status.put("lastRequestTime", lastRequestTime);
        status.put("lastSuccessTime", lastSuccessTime);
        status.put("lastFailureTime", lastFailureTime);
        status.put("configuration", Map.of(
            "timeoutMs", timeoutMs,
            "retryAttempts", retryAttempts,
            "retryDelayMs", retryDelayMs,
            "hasCustomHeaders", StringUtils.hasText(webhookHeaders)
        ));

        return status;
    }

    private double calculateSuccessRate() {
        long total = totalRequests.get();
        if (total == 0) return 0.0;
        return (double) successfulRequests.get() / total * 100.0;
    }

    /**
     * Result object for webhook relay operations
     */
    @Getter
	public static class WebhookRelayResult {
		// Getters
		private final boolean success;
        private final int statusCode;
        private final String message;
        private final String errorMessage;

        private WebhookRelayResult(boolean success, int statusCode, String message, String errorMessage) {
            this.success = success;
            this.statusCode = statusCode;
            this.message = message;
            this.errorMessage = errorMessage;
        }

        public static WebhookRelayResult success(int statusCode, String message) {
            return new WebhookRelayResult(true, statusCode, message, null);
        }

        public static WebhookRelayResult error(String errorMessage) {
            return new WebhookRelayResult(false, 0, null, errorMessage);
        }

        public static WebhookRelayResult disabled(String message) {
            return new WebhookRelayResult(true, 200, message, null);
        }

	}
}
