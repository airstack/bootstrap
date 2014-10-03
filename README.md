Common library and defaults for developing and building Airstack images.

Used by both the CLI and Airstack images repos as a common
library for building images and initializing defaults.

Bootstrap eliminates the need for duplicating Makefiles and other
common scripts and templates. It also makes it possible to use Airstack
images without first installing the CLI.


# Install

```bash
curl -s https://raw.githubusercontent.com/airstack/bootstrap/master/install | sh -e
```

This will install node, bootstrap, and cli.
