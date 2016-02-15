#!/usr/bin/env bash
# Copyright 2016 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
#
# This script is used by nightly and release jobs on ci.tensorflow.org


# Figure out the directory where this script is.
SCRIPT_DIR=$( cd ${0%/*} && pwd -P )

# Helper functions.
function cleanup_string() {
  echo -e "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]'
}

# CI_BUILD_MATRIX_LABEL overrides both CI_PLATFORM and CI_PROCESSING_UNIT
# It is useful for nightly and release builds at ci.tensorflow.org
CI_BUILD_MATRIX_LABEL=$( cleanup_string "${CI_BUILD_MATRIX_LABEL}" )
case "${CI_BUILD_MATRIX_LABEL}" in
  cpu-slave ) CI_PLATFORM=DOCKER ; CI_PROCESSING_UNIT=CPU ;;
  gpu-slave ) CI_PLATFORM=DOCKER ; CI_PROCESSING_UNIT=GPU ;;
  mac-slave ) CI_PLATFORM=MAC ;    CI_PROCESSING_UNIT=CPU ;;
esac

# Cleanup configuration.
CI_PLATFORM=$( cleanup_string "${CI_PLATFORM}" )
CI_PROCESSING_UNIT=$( cleanup_string "${CI_PROCESSING_UNIT}" )
CI_BUILD_PYTHON=$( cleanup_string "${CI_BUILD_PYTHON}" )
CI_BUILD=$( cleanup_string "${CI_BUILD}" )

# Print configuration.
echo "CI_BUILD_MATRIX_LABEL: ${CI_BUILD_MATRIX_LABEL}"
echo "CI_PLATFORM: ${CI_PLATFORM}"
echo "CI_PROCESSING_UNIT: ${CI_PROCESSING_UNIT}"
echo "CI_BUILD_PYTHON: ${CI_BUILD_PYTHON}"
echo "CI_BUILD: ${CI_BUILD}"
echo ""

# Validate configuration (and print usage if needed).
if [[ ! "${CI_PLATFORM}" =~ ^(docker|mac|linux|android)$ ]] || \
    [[ ! "${CI_PROCESSING_UNIT}" =~ ^(cpu|gpu)$ ]] || \
    [[ ! "${CI_BUILD_PYTHON}" =~ ^(python2|python3)$ ]] || \
    [[ ! "${CI_BUILD}" =~ ^(bazel|pip)$ ]]; then
  >&2 echo "Usage: [VARIABLE=VALUE]* $(basename $0)"
  >&2 echo ""
  >&2 echo "Note all these environment variables have to be defined:"
  >&2 echo "  CI_PLATFORM: (DOCKER | MAC | LINUX | ANDROID)"
  >&2 echo "  CI_PROCESSING_UNIT: (CPU | GPU)"
  >&2 echo "  CI_BUILD_PYTHON: (PYTHON2 | PYTHON3)"
  >&2 echo "  CI_BUILD: (BAZEL | PIP)"
  exit 1
fi

# Compute build.
build="${CI_PLATFORM}_${CI_PROCESSING_UNIT}_${CI_BUILD_PYTHON}_${CI_BUILD}"

# Run desired build.
case "${build}" in
  # Exit on unuspported builds.
  android_* | mac_gpu_* )
    >&2 echo "ERROR: Unsupported build ${build}!"
    exit 1
    ;;

  # CI_PLATFORM specific stuff
  docker_* )
    wrapper="tensorflow/tools/ci_build/ci_build.sh ${CI_PROCESSING_UNIT}"
    export CI_DOCKER_IMAGE_NAME="ci_matrix_build-${build}"
    ;;&
  mac_* )
    export BAZELRC="${SCRIPT_DIR}/install/.bazelrc.mac"
    export PATH="$PATH:/usr/local/bin"
    ;;&
  mac_* | linux_* | android_* )
    wrapper="tensorflow/tools/ci_build/builds/configured"
    ;;&

  # CI_PROCESSING_UNIT and CI_BUILD specific stuff
  *_cpu_*_bazel)
    cmd="bazel test //tensorflow/..."
    ;;&
  *_gpu_*_bazel)
    # run gpu tests in sequence since each of them eat all available gpu memory
    cmd="bash -c 'bazel build -c opt --config=cuda //tensorflow/... && bazel test --jobs=1 -c opt --config=cuda --test_tag_filters=local //tensorflow/...'"
    ;;&
  *_pip)
    cmd="tensorflow/tools/ci_build/builds/pip.sh ${CI_PROCESSING_UNIT}"
    ;;&

  # CI_BUILD_PYTHON specific stuff
  *_python3_*)
    export CI_DOCKER_EXTRA_PARAMS="${CI_DOCKER_EXTRA_PARAMS[@]} -e CI_BUILD_PYTHON=python3"
    export CI_BUILD_PYTHON=python3
    ;;&
esac

echo "CI_DOCKER_EXTRA_PARAMS='${CI_DOCKER_EXTRA_PARAMS}' ${wrapper} ${cmd}"
#CI_DOCKER_EXTRA_PARAMS=${CI_DOCKER_EXTRA_PARAMS} ${wrapper} ${cmd}
${wrapper} ${cmd}
