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
  # Language Fonts
  ttf-ancient-fonts fonts-beng fonts-wqy-zenhei fonts-indic \
  ; \
  # If any Python cryptography landed anyway, purge it
  if dpkg -l | grep -q '^ii\s\+python3-cryptography\s'; then \
  apt-get purge -y python3-cryptography || true; \
  apt-mark hold python3-cryptography || true; \
  fi; \
  rm -rf /var/lib/apt/lists/*

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

# Copy scripts
COPY entrypoint.sh scripts/composed.sh  ./
COPY utils/xvfb-run-safe /usr/local/bin
COPY utils/headless-chrome.sh ./

# Prepare scripts and folders
RUN chmod +x /entrypoint.sh /composed.sh /headless-chrome.sh \
  && chmod +x /usr/local/bin/xvfb-run-safe \
  && mkdir -p /recordings \
  && chmod 777 /recordings

ENTRYPOINT ["/entrypoint.sh"]
