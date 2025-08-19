package com.naevatec.ovrecorder;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class OvRecorderApplication {

  public static void main(String[] args) {
    SpringApplication.run(OvRecorderApplication.class, args);
  }
}