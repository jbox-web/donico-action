# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# donico passes DISTRO_NAME, BUILD_DATE and EXAMPLE_VERSION as build args.
ARG DISTRO_NAME
FROM debian:${DISTRO_NAME}-slim

ARG BUILD_DATE
ARG EXAMPLE_VERSION
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.version="${EXAMPLE_VERSION}"

# The platform the image was built for, read back by the end-to-end job.
RUN uname -m > /etc/donico-action-example
