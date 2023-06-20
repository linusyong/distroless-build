#!/usr/bin/env bash

BUILD_NAME=python3-git
IMAGE_NAME=linusyong/${BUILD_NAME}

[[ -d grype-cache ]] || { mkdir grype-cache; chmod 777 grype-cache; }

## Docker build (BuildKit)
echo "Starting Docker build..." | tee -a build-${BUILD_NAME}.log

docker build \
  --no-cache \
  --progress=plain \
  . -f Dockerfile.python3-git \
  -t ${IMAGE_NAME}-docker-build \
  2>&1 | tee -a build-${BUILD_NAME}.log

docker save ${IMAGE_NAME}-docker-build -o ${BUILD_NAME}-docker-build.tar \
  | tee -a build-${BUILD_NAME}.log


## Kaniko build
echo "Starting Kaniko build..." | tee -a build-${BUILD_NAME}.log

docker run -it --rm \
  -v $(pwd):/workdir \
  -v $(pwd)/contariner_registry.json:/kaniko/.docker/config.json:ro \
  gcr.io/kaniko-project/executor \
  --dockerfile /workdir/Dockerfile.python3-git \
  --context /workdir \
  --snapshot-mode=redo \
  --destination=${IMAGE_NAME} \
  --tar-path=/workdir/${BUILD_NAME}-kaniko-build.tar \
  --no-push \
  | tee -a build-${BUILD_NAME}.log

docker load -i ${BUILD_NAME}-kaniko-build.tar \
  | tee -a build-${BUILD_NAME}.log


## Apko build
echo "Starting Apko build..." | tee -a build-${BUILD_NAME}.log

docker run -it --rm \
  -v $(pwd):/workdir \
  cgr.dev/chainguard/apko \
  --sbom=false \
  --build-date="$(date --rfc-3339=seconds | sed 's/ /T/')" \
  build /workdir/${BUILD_NAME}.yaml "${IMAGE_NAME}-apko-build" /workdir/${BUILD_NAME}-apko-build.tar \
  | tee -a build-${BUILD_NAME}.log

docker load -i ${BUILD_NAME}-apko-build.tar \
  | tee -a build-${BUILD_NAME}.log

## Generate SBOM with syft
echo "Starting syft SBOM generation..." | tee -a build-${BUILD_NAME}.log

docker run \
  -v $(pwd):/workdir \
  --rm anchore/syft \
  docker-archive:/workdir/${BUILD_NAME}-docker-build.tar \
  -o spdx-json=/workdir/${BUILD_NAME}-docker-build-syft-output-spdx.json \
  | tee -a build-${BUILD_NAME}.log

docker run \
  -v $(pwd):/workdir \
  --rm anchore/syft \
  docker-archive:/workdir/${BUILD_NAME}-kaniko-build.tar \
  -o spdx-json=/workdir/${BUILD_NAME}-kaniko-build-syft-output-spdx.json \
  | tee -a build-${BUILD_NAME}.log

docker run \
  -v $(pwd):/workdir \
  --rm anchore/syft \
  docker-archive:/workdir/${BUILD_NAME}-apko-build.tar \
  -o spdx-json=/workdir/${BUILD_NAME}-apko-build-syft-output-spdx.json \
  | tee -a build-${BUILD_NAME}.log

## Vulnerability scan with grype
echo "Starting grype vulnerability scan..." | tee -a build-${BUILD_NAME}.log

echo "Scanning docker-build..." | tee -a build-${BUILD_NAME}.log
docker run \
  -v $(pwd)/${BUILD_NAME}-docker-build-syft-output-spdx.json:/workdir/${BUILD_NAME}-docker-build-syft-output-spdx.json \
  -v $(pwd)/grype-cache:/.cache \
  --rm anchore/grype:latest \
  --only-fixed /workdir/${BUILD_NAME}-docker-build-syft-output-spdx.json \
  --add-cpes-if-none \
  | tee -a build-${BUILD_NAME}.log

echo "Scanning kaniko-build..." | tee -a build-${BUILD_NAME}.log
docker run \
  -v $(pwd)/${BUILD_NAME}-kaniko-build-syft-output-spdx.json:/workdir/${BUILD_NAME}-kaniko-build-syft-output-spdx.json \
  -v $(pwd)/grype-cache:/.cache \
  --rm anchore/grype:latest \
  --only-fixed /workdir/${BUILD_NAME}-kaniko-build-syft-output-spdx.json \
  --add-cpes-if-none \
  | tee -a build-${BUILD_NAME}.log

echo "Scanning apko-build..." | tee -a build-${BUILD_NAME}.log
docker run \
  -v $(pwd)/${BUILD_NAME}-apko-build-syft-output-spdx.json:/workdir/${BUILD_NAME}-apko-build-syft-output-spdx.json \
  -v $(pwd)/grype-cache:/.cache \
  --rm anchore/grype:latest \
  --only-fixed /workdir/${BUILD_NAME}-apko-build-syft-output-spdx.json \
  --add-cpes-if-none \
  | tee -a build-${BUILD_NAME}.log
