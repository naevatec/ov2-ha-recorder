FROM ubuntu:24.04

LABEL maintainer="NaevaTec-OpenVidu eiglesia@openvidu.io"

ENV DEBIAN_FRONTEND=noninteractive

# Base packages (no recommends to avoid extra Python deps like python3-cryptography)
RUN set -eux; \
  apt-get update; \
  apt-get -y upgrade; \
  apt-get install -y --no-install-recommends \
  ca-certificates \
  wget \
  sudo \
  gnupg2 \
  apt-utils \
  software-properties-common \
  ffmpeg \
  pulseaudio \
  xvfb \
  jq \
  # Additional packages for chunk uploading
  inotify-tools \
  unzip \
  curl \
  # Language Fonts
  ttf-ancient-fonts fonts-beng fonts-wqy-zenhei fonts-indic \
  ; \
  # If any Python cryptography landed anyway, purge it
  if dpkg -l | grep -q '^ii\s\+python3-cryptography\s'; then \
  apt-get purge -y python3-cryptography || true; \
  apt-mark hold python3-cryptography || true; \
  fi; \
  rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 for S3 uploads (compatible with MinIO and other S3-compatible services)
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
  && unzip awscliv2.zip \
  && ./aws/install \
  && rm -rf awscliv2.zip aws

# Install latest stable Chrome (signed repo, no apt-key)
RUN set -eux; \
  mkdir -p /etc/apt/keyrings; \
  wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor \
  > /etc/apt/keyrings/google-linux-signing-key.gpg; \
  chmod 0644 /etc/apt/keyrings/google-linux-signing-key.gpg; \
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux-signing-key.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
  > /etc/apt/sources.list.d/google-chrome.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends google-chrome-stable; \
  # Re-purge in case the Chrome install pulled python3-cryptography via recommends
  if dpkg -l | grep -q '^ii\s\+python3-cryptography\s'; then \
  apt-get purge -y python3-cryptography || true; \
  apt-mark hold python3-cryptography || true; \
  fi; \
  rm -rf /var/lib/apt/lists/*

# Add root user to pulseaudio group (group is created by pulseaudio package)
RUN adduser root pulse-access

# Clean
RUN apt-get clean && apt-get autoclean && apt-get autoremove -y

# Create log directory for chunk uploader and other services
RUN mkdir -p /var/log && chmod 755 /var/log

# Copy scripts and utilities
COPY entrypoint.sh scripts/composed.sh ./
COPY utils/xvfb-run-safe /usr/local/bin/
COPY utils/headless-chrome.sh ./
COPY utils/chunk-uploader.sh /usr/local/bin/
COPY utils/chunk-downloader.sh /usr/local/bin/
COPY utils/chunk-cleaner.sh /usr/local/bin/
COPY utils/log-uploader.sh /usr/local/bin/
COPY utils/logging.sh /usr/local/bin/
COPY utils/session-register.sh /usr/local/bin/
COPY utils/recorder-session-manager.sh /usr/local/bin/

# Prepare scripts and folders
RUN chmod +x /entrypoint.sh /composed.sh /headless-chrome.sh \
  && chmod +x /usr/local/bin/xvfb-run-safe \
  && chmod +x /usr/local/bin/chunk-uploader.sh \
  && chmod +x /usr/local/bin/chunk-downloader.sh \
  && chmod +x /usr/local/bin/chunk-cleaner.sh \
  && chmod +x /usr/local/bin/log-uploader.sh \
  && chmod +x /usr/local/bin/logging.sh \
  && chmod +x /usr/local/bin/session-register.sh \
  && chmod +x /usr/local/bin/recorder-session-manager.sh \
  && mkdir -p /recordings \
  && chmod 777 /recordings

ENTRYPOINT ["/entrypoint.sh"]