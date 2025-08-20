package com.naevatec.ovrecorder.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

import java.util.List;

@Configuration
@Profile("!prod") // Only activate when NOT in production profile
@ConditionalOnProperty(value = "springdoc.api-docs.enabled", havingValue = "true", matchIfMissing = false)
public class SwaggerConfig {

  @Value("${app.api.title:OV Recorder HA Controller API}")
  private String apiTitle;

  @Value("${app.api.description:High Availability Controller for OpenVidu Substitute Recording Sessions}")
  private String apiDescription;

  @Value("${app.api.version:1.0.0}")
  private String apiVersion;

  @Value("${app.api.contact.name:Naevatec Development Team}")
  private String contactName;

  @Value("${app.api.contact.email:dev@naevatec.com}")
  private String contactEmail;

  @Value("${server.port:8080}")
  private int serverPort;

  @Bean
  public OpenAPI customOpenAPI() {
    return new OpenAPI()
        .info(new Info()
            .title(apiTitle)
            .description(apiDescription)
            .version(apiVersion)
            .contact(new Contact()
                .name(contactName)
                .email(contactEmail))
            .license(new License()
                .name("Proprietary")
                .url("https://naevatec.com")))
        .servers(List.of(
            new Server()
                .url("http://localhost:" + serverPort)
                .description("Development Server"),
            new Server()
                .url("https://your-domain.com")
                .description("Production Server")))
        .addSecurityItem(new SecurityRequirement()
            .addList("basicAuth"))
        .components(new io.swagger.v3.oas.models.Components()
            .addSecuritySchemes("basicAuth",
                new SecurityScheme()
                    .type(SecurityScheme.Type.HTTP)
                    .scheme("basic")
                    .description("HTTP Basic Authentication using username and password")));
  }
}
