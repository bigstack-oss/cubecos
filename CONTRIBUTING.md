# CONTRIBUTING

Thanks for your interest in contributing to CubeCOS. To create an open space for the community, we ask that you read through and follow the guidelines in this document.

## Contents

- [CONTRIBUTING](#contributing)
  - [Contents](#contents)
  - [Code of conduct](#code-of-conduct)
  - [Prerequisites](#prerequisites)
    - [Create a GitHub account](#create-a-github-account)
    - [Setup Git commit signing](#setup-git-commit-signing)
  - [How to contribute](#how-to-contribute)
    - [Sign your commits](#sign-your-commits)
  - [Development](#development)
    - [Hardware requirements](#hardware-requirements)
    - [Software requirements](#software-requirements)
    - [Clone the code](#clone-the-code)
    - [Build artifacts](#build-artifacts)
    - [Troubleshooting](#troubleshooting)

## Code of conduct

We strive to maintain a positive community, guided by our [CODE OF CONDUCT](/CODE_OF_CONDUCT.md).

You can reach out to us at [community@bigstack.co](mailto:community@bigstack.co)

## Prerequisites

### Create a GitHub account

Create a [GitHub](https://github.com/signup) account if you haven't already.

### Setup Git commit signing

Git commit signing is a process that uses cryptographic signatures (GPG or SSH keys) to verify the authenticity of a commits' author, ensuring that the commit was created by a trusted identity and hasn’t been tampered with. We require our contributors to sign their commits to stay secure and validate developer origin certificate sign offs. Setup [Git commit signing](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)

## How to contribute

We welcome contributions in the form of:

- New features
- Bug fix or feature enhancement
- Issue Triage
- Documentation
- Answering questions in Slack or Discord
- Communications / Social media / Blog posts

Please **do not** report any **security** issues in the issue tracker or a pull request. Please follow our [security](/SECURITY.md) policy on how to report and reach us.

### Sign your commits

We adopt the [Developer Origin Certificate v1.1](https://developercertificate.org/) to ensure contributions are properly authorized and compliant with open-source standards.

Git commit sign-off is a declaration by you that you adhere to the Developer Certificate of Origin (DCO), adding a `Signed-off-by:` line in the commit message to confirm you authored or have permission to contribute the changes.

You sign-off by adding the following to your commit messages. Your sign-off must match the git user and email associated with the commit.

```bash
This is my commit message

Signed-off-by: Your Name <your.name@example.com>
```

The DCO is done automatically with the `--signoff (-s)` in Git with

```bash
git commit -s -m "Description of the commit"
```

## Development

The development environment runs CubeCOS in a containerized instance, which requires substantial memory resources to operate reliably. The following specifications apply only to the development environment’s software and hardware requirements.

For production deployments and full CubeCOS setup details, refer to the [Installation](https://docs.bigstack.co/docs/cubecos/installation/overview) section of the CubeCOS documentation.

### Hardware requirements

- CPU
  - Architecture: x86_64
  - 8C/16T cores, 2.0 GHz or higher
  - Hardware virtualization support (Intel VT-x/ AMD-V support)
- Memory
  - Minimum: 64 GiB
- Disk
  - Minimum: 500 GiB free space

### Software requirements

- Host operating system
  - CentOS 8
  - CentOS Stream 8
  - CentOS Stream 9
- Git
- Git LFS
- Docker (docker-ce)

### Clone the code

Clone repositories with the recursive flag to include all sub-modules.

```bash
git clone --recursive git@github.com:bigstack-oss/cubecos.git
```

### Build artifacts

1. Create and enter jail

    The default project name is `centos9-jail`, the build process will create a new folder with the default project name in the same path as CubeCOS repository.

    To build with default project name and enter the built container, use:

    ```bash
    cd cubecos
    make centos9-jail enter
    ```

    To build with a custom project name, useful for multiple deployment streams or testing scenarios:

    ```bash
    cd cubecos
    make PROJECT=your-project-name centos9-jail enter
    ```

    If no `PROJECT` name is specified, the build will default to centos9-jail, creating both a build directory and container with that name.

    Once the jail is created, you’ll see two directories under the parent path:

    - `cubecos/` – The main source repository
    - `centos9-jail/` (or your custom project name) – The isolated build environment

    ```bash
    build-bench > ls ..
    cubecos centos9-jail
    ```

    Running `make PROJECT=example centos9-jail` will create a new build jail named example. The corresponding build folder will also be named example and will be created in the parent directory of the cubecos folder.

    `make PROJECT=example centos9-jail` would create another jail named `example`, and the build folder would be `example` under the parent directory of folder `cubecos`

    ```bash
    cubecos> ls ..
    cubecos centos9-jail example
    ```

    We could use the command `make enter` to enter the default build jail `centos9-jail`. Alternatively, `make PROJECT=example enter` would bring us into the build jail `example`.

2. Build various CubeCOS install media by specifying the build parameters.

    The build command can only be executed in the CubeCOS build jail. Create and enter a jail or enter an existing jail before attempting to generate CubeCOS installation media. The build command can produce the following installation media types:

   1. `full`: Builds all supported CubeCOS installation media (ISO, USB, PXE, and package files).
   2. `pxe`: Produces network boot files for provisioning systems via PXE servers.  
   3. `pxeserver`: Build a complete PXE server image for hosting network boot files.  
   4. `pxeserveriso`: Build an ISO version of the PXE server image.  
   5. `usb`: Creates a USB bootable image for physical installations via USB drives.
   6. `iso`: Generates an ISO image for use as virtual media.
   7. `liveusb`: Build a live USB image for running CubeCOS directly without installation.

    ```bash
    # all installation types
    [root@centos9-jail centos9-jail]# make full

    # network boot
    [root@centos9-jail centos9-jail]# make pxe

    # usb media
    [root@centos9-jail centos9-jail]# make usb

    # iso generation
    [root@centos9-jail centos9-jail]# make iso
    ```

3. Locate artifacts

    Build artifacts could be located under `core/main/ship` inside the build folder.

   - CUBE_XXX.img: The USB installer
     - Flash it to an USB stick using `dd bs=4M if=<img_file_path> of=<usb_device_name> status=progress oflag=sync`
     - Boot a server using the USB stick
     - Follow [Login and restore to setup CubeCOS](https://docs.bigstack.co/docs/cubecos/quick-start/single-node#login-and-restore-to-setup-cubecos) to flash the system partition.
   - CUBE_XXX.iso: CubeCOS ISO
   - CUBE_XXX.pkg: CubeCOS file system archive
   - CUBE_XXX.pxe.tgz: The archive containing components to set up a PXE server to install CubeCOS using PXE

    MD5 hashes are also provided to each artifacts under `core/main/ship`.

4. To clean up builds

    ```bash
    make distclean
    ```

  > Note
  >
  > While re-entering the jail, or in any circumstances to clean up build remnants, it is recommended to use `make distclean` to clean up previous build artifacts.

### Troubleshooting

Other than git-lfs, make sure [hex](https://github.com/bigstack-oss/hex) (git sub-module) is properly cloned under your top source directory.

```bash
ls -lt cubecos/hex
```
