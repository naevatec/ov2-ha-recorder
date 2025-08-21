package com.naevatec.ovrecorder.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.concurrent.Executor;
import java.util.concurrent.ThreadPoolExecutor;

@Configuration
@EnableAsync
@Slf4j
public class AsyncConfig {

    @Value("${app.webhook.thread-pool.core-size:5}")
    private int webhookCorePoolSize;

    @Value("${app.webhook.thread-pool.max-size:20}")
    private int webhookMaxPoolSize;

    @Value("${app.webhook.thread-pool.queue-capacity:100}")
    private int webhookQueueCapacity;

    @Value("${app.webhook.thread-pool.keep-alive:60}")
    private int webhookKeepAliveSeconds;

    /**
     * Dedicated thread pool for webhook relay operations
     * Optimized for high throughput and low latency
     */
    @Bean("webhookExecutor")
    public Executor webhookExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();

        // Core pool size - always active threads
        executor.setCorePoolSize(webhookCorePoolSize);

        // Maximum pool size - peak load handling
        executor.setMaxPoolSize(webhookMaxPoolSize);

        // Queue capacity - requests waiting for processing
        executor.setQueueCapacity(webhookQueueCapacity);

        // Keep alive time for excess threads
        executor.setKeepAliveSeconds(webhookKeepAliveSeconds);

        // Thread naming for debugging
        executor.setThreadNamePrefix("webhook-relay-");

        // Rejection policy - caller runs (ensures no webhook is lost)
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());

        // Wait for tasks to complete on shutdown
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(30);

        // Allow core threads to timeout when idle
        executor.setAllowCoreThreadTimeOut(true);

        executor.initialize();

        log.info("Webhook relay executor configured: core={}, max={}, queue={}, keepAlive={}s",
            webhookCorePoolSize, webhookMaxPoolSize, webhookQueueCapacity, webhookKeepAliveSeconds);

        return executor;
    }

    /**
     * General purpose async executor for other async operations
     */
    @Bean("taskExecutor")
    public Executor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(10);
        executor.setQueueCapacity(50);
        executor.setKeepAliveSeconds(60);
        executor.setThreadNamePrefix("async-task-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(30);
        executor.initialize();

        log.info("General task executor configured: core=2, max=10, queue=50");

        return executor;
    }
}
