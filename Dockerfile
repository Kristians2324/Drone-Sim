FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV GODOT_VERSION=4.6.2
ENV GODOT_ZIP=Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
ENV GODOT_URL=https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${GODOT_ZIP}
ENV GODOT_HOME=/opt/godot

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    xvfb \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libxi6 \
    libglib2.0-0 \
    libgtk-3-0 \
    libasound2 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${GODOT_HOME} /workspace
WORKDIR /workspace

RUN curl -L ${GODOT_URL} -o /tmp/godot.zip \
    && unzip /tmp/godot.zip -d ${GODOT_HOME} \
    && rm /tmp/godot.zip \
    && mv ${GODOT_HOME}/Godot_v${GODOT_VERSION}-stable_linux.x86_64 ${GODOT_HOME}/godot \
    && chmod +x ${GODOT_HOME}/godot

ENV PATH="${GODOT_HOME}:${PATH}"

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["godot", "--headless", "--path", "/workspace"]