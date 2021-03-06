#!/bin/bash
set -eE

DOCKER_TIMEOUT=30
DOCKER_PID=0


function start_docker() {
    local starttime
    local endtime

    echo "Starting docker."
    dockerd 2> /dev/null &
    DOCKER_PID=$!

    echo "Waiting for docker to initialize..."
    starttime="$(date +%s)"
    endtime="$(date +%s)"
    until docker info >/dev/null 2>&1; do
        if [ $((endtime - starttime)) -le $DOCKER_TIMEOUT ]; then
            sleep 1
            endtime=$(date +%s)
        else
            echo "Timeout while waiting for docker to come up"
            exit 1
        fi
    done
    echo "Docker was initialized"
}


function stop_docker() {
    local starttime
    local endtime

    echo "Stopping in container docker..."
    if [ "$DOCKER_PID" -gt 0 ] && kill -0 "$DOCKER_PID" 2> /dev/null; then
        starttime="$(date +%s)"
        endtime="$(date +%s)"

        # Now wait for it to die
        kill "$DOCKER_PID"
        while kill -0 "$DOCKER_PID" 2> /dev/null; do
            if [ $((endtime - starttime)) -le $DOCKER_TIMEOUT ]; then
                sleep 1
                endtime=$(date +%s)
            else
                echo "Timeout while waiting for container docker to die"
                exit 1
            fi
        done
    else
        echo "Your host might have been left with unreleased resources"
    fi
}


function build_supervisor() {
    docker pull homeassistant/amd64-builder:dev

    docker run --rm --privileged \
        -v /run/docker.sock:/run/docker.sock -v "$(pwd):/data" \
        homeassistant/amd64-builder:dev \
            --supervisor 3.7-alpine3.11 --version dev \
            -t /data --test --amd64 \
            --no-cache --docker-hub homeassistant
}


function cleanup_lastboot() {
    if [[ -f /workspaces/test_supervisor/config.json ]]; then
        echo "Cleaning up last boot"
        cp /workspaces/test_supervisor/config.json /tmp/config.json
        jq -rM 'del(.last_boot)' /tmp/config.json > /workspaces/test_supervisor/config.json
        rm /tmp/config.json
    fi
}


function cleanup_docker() {
    echo "Cleaning up stopped containers..."
    docker rm $(docker ps -a -q)
}


function install_cli() {
    docker pull homeassistant/amd64-hassio-cli:dev
}


function setup_test_env() {
    mkdir -p /workspaces/test_supervisor

    echo "Start Supervisor"
    docker run --rm --privileged \
        --name hassio_supervisor \
        --security-opt seccomp=unconfined \
        --security-opt apparmor:unconfined \
        -v /run/docker.sock:/run/docker.sock \
        -v /run/dbus:/run/dbus \
        -v "/workspaces/test_supervisor":/data \
        -v /etc/machine-id:/etc/machine-id:ro \
        -e SUPERVISOR_SHARE="/workspaces/test_supervisor" \
        -e SUPERVISOR_NAME=hassio_supervisor \
        -e SUPERVISOR_DEV=1 \
        -e HOMEASSISTANT_REPOSITORY="homeassistant/qemux86-64-homeassistant" \
        homeassistant/amd64-hassio-supervisor:latest

}

echo "Start Test-Env"

start_docker
trap "stop_docker" ERR

build_supervisor
install_cli
cleanup_lastboot
cleanup_docker
setup_test_env
stop_docker
