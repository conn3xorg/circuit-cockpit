# Local example

Applies circuit-cockpit to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

Cockpit's units use systemd sandboxing, which needs namespaces, so the host container runs privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` Cockpit listens on 9090 inside the container, which `up.sh` doesn't publish, so look at it from in there. Root can't log in to Cockpit, so make a user to try it with:

```sh
ssh -p 2296 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1
useradd -m tester && passwd tester
curl -k -u tester https://127.0.0.1:9090/cockpit/login
```

`up.sh` listens on `127.0.0.1:2296`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
