FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV GODOT_VERSION=4.7-stable
ENV GODOT_BINARY=Godot_v${GODOT_VERSION}_linux.x86_64
ENV GODOT_TARBALL=${GODOT_BINARY}.tar.xz
ENV GODOT_URL=https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_TARBALL}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xz-utils \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libxi6 \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/godot

RUN curl --retry 5 --retry-delay 2 --fail -L -o /tmp/${GODOT_TARBALL} "${GODOT_URL}" \
    && tar -xJf /tmp/${GODOT_TARBALL} -C /usr/local/bin \
    && mv /usr/local/bin/${GODOT_BINARY} /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/${GODOT_TARBALL}

WORKDIR /workspace

COPY . /workspace

ENTRYPOINT ["godot", "--headless"]

# Default to opening the project in headless mode.
# Override at runtime for exports, tests, or custom commands.
CMD ["--path", "/workspace"]