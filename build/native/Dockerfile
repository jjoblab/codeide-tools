# build/native/Dockerfile — image de build natif des outils SDK (ADR 0012).
#
# Épinglages :
#   - base : ubuntu:24.04 par DIGEST (amd64 — le build croisé tourne sur hôte x86_64)
#   - NDK  : r27c (27.2.12479018) par URL versionnée Google — même lignée que les
#     binaires v1 mesurés (ELF « for Android 30 », NDK r27b) ;
#   - paquets apt : versions du jour du build de l'image (journalisées par
#     `docker image inspect`) — compromis documenté : l'outillage qui compte
#     pour le résultat binaire (NDK + sources AOSP + recette) est épinglé.
#
# La recette (CMakeLists, *.cmake, patches/, get_source.py, build.py) n'est PAS
# dans l'image : elle est montée en lecture seule depuis le dépôt (le commit du
# dépôt est le pin de la recette).

FROM ubuntu:24.04@sha256:f610ab94648195aa356059f5b41d6085c9d4d903c072430cdd1af7bdb646106b

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config \
        git golang-go bison flex cmake ninja-build \
        python3 python3-pip unzip file xz-utils \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# NDK épinglé (r27c) — l'archive est immuable côté Google (URL versionnée).
ADD https://dl.google.com/android/repository/android-ndk-r27c-linux.zip /tmp/ndk.zip
RUN unzip -q /tmp/ndk.zip -d /opt && rm -f /tmp/ndk.zip \
    && mv /opt/android-ndk-r27c /opt/ndk
ENV ANDROID_NDK=/opt/ndk

WORKDIR /work
