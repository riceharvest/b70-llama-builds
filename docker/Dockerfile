# llama.cpp for the Intel Arc Pro B70: the b70-llama-builds SYCL + Vulkan binaries on a pinned Arch Linux snapshot, so the
# container brings its own recent GPU userspace: Mesa ANV 26.2.x (Vulkan), compute-runtime + Level Zero (SYCL).
# Only the kernel driver (xe) comes from the host. Built by .github/workflows/image.yml from a b70-llama-builds release.
FROM archlinux:base
ARG ARCH_SNAPSHOT=2026/10/14
RUN echo "Server = https://archive.archlinux.org/repos/${ARCH_SNAPSHOT}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist \
 && pacman -Syyuu --noconfirm \
 && pacman -S --noconfirm --needed vulkan-intel vulkan-icd-loader vulkan-tools intel-compute-runtime level-zero-loader curl \
 && rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*
ARG RELEASE_TAG=unknown
COPY dist/llama-b70-sycl-ubuntu24-x64.tar.gz dist/llama-b70-vulkan-ubuntu24-x64.tar.gz dist/SHA256SUMS /tmp/dist/
RUN cd /tmp/dist && sha256sum -c SHA256SUMS \
 && mkdir -p /opt/llama \
 && tar -xzf llama-b70-sycl-ubuntu24-x64.tar.gz -C /opt/llama && mv /opt/llama/llama-b70-sycl-ubuntu24-x64 /opt/llama/sycl \
 && tar -xzf llama-b70-vulkan-ubuntu24-x64.tar.gz -C /opt/llama && mv /opt/llama/llama-b70-vulkan-ubuntu24-x64 /opt/llama/vulkan \
 && rm -rf /tmp/dist && echo "$RELEASE_TAG" > /opt/llama/RELEASE
COPY b70-llama /usr/local/bin/b70-llama
ENV ONEAPI_DEVICE_SELECTOR=level_zero:gpu
WORKDIR /models
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/b70-llama"]
CMD ["help"]
