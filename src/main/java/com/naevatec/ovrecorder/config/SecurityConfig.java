package com.naevatec.ovrecorder.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

import static org.springframework.security.config.Customizer.withDefaults;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

  @Value("${app.security.username:recorder}")
  private String username;

  @Value("${app.security.password:rec0rd3r_2024!}")
  private String password;

  @Bean
  public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
        .csrf(AbstractHttpConfigurer::disable) // Disable CSRF for API usage
        .authorizeHttpRequests(authz -> authz
            // Health check endpoints (no auth required)
            .requestMatchers("/actuator/health").permitAll()
            .requestMatchers("/api/sessions/health").permitAll()

            // OpenVidu Webhook endpoints (no auth required - OpenVidu doesn't send auth)
            .requestMatchers("/openvidu/webhook/**").permitAll()

            // Swagger/OpenAPI endpoints (no auth required for documentation)
            .requestMatchers("/swagger-ui/**").permitAll()
            .requestMatchers("/swagger-ui.html").permitAll()
            .requestMatchers("/api-docs/**").permitAll()
            .requestMatchers("/v3/api-docs/**").permitAll()

            // All other requests require authentication
            .anyRequest().authenticated()
        )
        .httpBasic(withDefaults()); // Enable HTTP Basic Authentication

    return http.build();
  }

  @Bean
  public UserDetailsService userDetailsService() {
    UserDetails user = User.builder()
        .username(username)
        .password(passwordEncoder().encode(password))
        .roles("USER", "ADMIN")
        .build();

    return new InMemoryUserDetailsManager(user);
  }

  @Bean
  public PasswordEncoder passwordEncoder() {
    return new BCryptPasswordEncoder();
  }
}
