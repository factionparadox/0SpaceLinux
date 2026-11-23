image := "localhost/0space:latest"

# Build the 0-Space image (rootful, so the ISO builder can see it).
build:
    sudo podman build -t {{image}} .

# Build an installer ISO from the image into ./output.
iso: build
    mkdir -p output
    sudo podman run --rm -it --privileged --pull=newer \
        --security-opt label=type:unconfined_t \
        -v ./output:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type anaconda-iso {{image}}
