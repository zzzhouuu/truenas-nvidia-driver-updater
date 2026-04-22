FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies required for extraction, kernel module compilation,
# and nvidia-container-toolkit installation (gnupg for apt repo key)
RUN apt-get update && apt-get install -y \
    build-essential wget curl squashfs-tools kmod xz-utils \
    bison flex libelf-dev bc rsync \
    libssl-dev pkg-config pciutils \
    gnupg ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
