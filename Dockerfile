FROM ubuntu:24.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Create a non-root user for building
RUN useradd -m vita

# Install sudo first and separately to avoid dependency issues in Docker
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo && \
    echo "vita ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    rm -rf /var/lib/apt/lists/*

# Install dependencies needed for vdpm and building packages
RUN apt-get update && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then LIBC32="libc6-dev-i386 gcc-multilib"; else LIBC32=""; fi && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    cmake \
    meson \
    ninja-build \
    make \
    patch \
    fakeroot \
    libarchive-tools \
    libtool-bin \
    xutils-dev \
    subversion \
    $LIBC32 \
    python3 \
    python3-pip \
    7zip \
    build-essential \
    autoconf \
    automake \
    autotools-dev \
    m4 \
    libtool \
    pkg-config \
    gperf \
    bison \
    flex \
    gettext \
    linux-libc-dev \
    libssl-dev \
    unzip \
    zlib1g-dev \
    libncurses-dev \
    libreadline-dev \
    libsqlite3-dev \
    libgdbm-dev \
    libdb5.3-dev \
    libbz2-dev \
    libexpat1-dev \
    liblzma-dev \
    tk-dev \
    libffi-dev \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends python3.11 python3.11-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python 2.7 from source
RUN wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tar.xz \
    && tar -xf Python-2.7.18.tar.xz \
    && cd Python-2.7.18 \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf Python-2.7.18*

# Clone and install VitaSDK
# We use the existing bootstrap-vitasdk.sh logic
ARG VITASDK_CACHE_BUST
RUN echo "VitaSDK Cache Bust: $VITASDK_CACHE_BUST" && \
    git clone --depth=1 https://github.com/vitasdk/vdpm.git /vdpm \
    && cd /vdpm \
    && bash bootstrap-vitasdk.sh \
    && rm -rf /vdpm

# Install the static rootless pacman client while the package-managed bootstrap
# is being introduced. Once autobuilds publishes vitasdk-core packages this
# transitional source build is removed from the image.
ARG BUILDSCRIPTS_REF=next
RUN git clone --depth=1 --branch "$BUILDSCRIPTS_REF" \
      https://github.com/vitasdk/buildscripts.git /buildscripts \
    && cmake -S /buildscripts -B /buildscripts/build-pacman \
      -DBUILD_PACMAN_CLIENT=ON \
      -DPACMAN_CLIENT_INSTALL_DIR=/pacman-client \
    && cmake --build /buildscripts/build-pacman \
      --target pacman-client-spike --parallel "$(nproc)" \
    && install -m755 /pacman-client/bin/pacman /usr/local/vitasdk/bin/pacman \
    && install -m755 /pacman-client/bin/pacman-conf \
      /usr/local/vitasdk/bin/pacman-conf \
    && rm -rf /buildscripts /pacman-client

ARG VITA_MAKEPKG_REF=master
RUN git clone --depth=1 --branch "$VITA_MAKEPKG_REF" \
      https://github.com/vitasdk/vita-makepkg.git /opt/vita-makepkg \
    && cp /opt/vita-makepkg/makepkg.conf.sample /opt/vita-makepkg/makepkg.conf \
    && ln -sf /opt/vita-makepkg/vita-makepkg /usr/local/vitasdk/bin/vita-makepkg \
    && install -d /usr/local/vitasdk/etc \
      /usr/local/vitasdk/var/lib/pacman \
      /usr/local/vitasdk/var/cache/pacman/pkg \
      /usr/local/vitasdk/var/log \
    && printf '%s\n' \
      '[options]' \
      'Architecture = auto vita' \
      'SigLevel = Never' \
      > /usr/local/vitasdk/etc/pacman.conf

# Set environment variables
ENV VITASDK=/usr/local/vitasdk
ENV PATH=$VITASDK/bin:$PATH

# Ensure the non-root user owns the vitasdk directory
RUN chown -R vita:vita /usr/local/vitasdk /opt/vita-makepkg

USER vita
WORKDIR /workspace
