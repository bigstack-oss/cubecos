# CubeCOS (Cube Cloud Operating System)

<div align="center">
<br/>
<br/>
<p align="center">
  <img width="234" alt="cubecos logo full" src="doc/media/logo-blue.png"/>
</p>

[![License][License-Image]][License-Url] [![Slack][Slack-Image]][Slack-Url] [![Discord][Discord-Image]][Discord-Url] [![Docs][Docs-Image]][Docs-Url] [![Website][Website-Image]][Website-Url] [![Youtube][Youtube-Image]][Youtube-Url]

<p align="center">
  <img width="80%" alt="cubecos interface introduction video" src="doc/media/cubecos-intro.gif"/>
</p>

</div>

CubeCOS is built for you: an open-source, out-of-the-box virtualization platform with simple management and the flexibility to integrate with anything.

Join us in building the future of software-defined infrastructure!

## ⚡️ Installation

Download CubeCOS from the [Release Page](https://github.com/bigstack-oss/cubecos/releases/tag/v3.0.0), and check out our [quick start installation](https://docs.bigstack.co/docs/cubecos/quick-start/overview) guide.

## 📚 Documentation

Get started by exploring our documentation at [CubeCOS documentation](https://docs.bigstack.co/docs/cubecos/getting-started/overview).

## 🚀 Features

- **Performant Virtualization**: A flexible hypervisor for virtual machines and containers based on QEMU/ KVM
- **Multi-Tenant Architectur**: Create secure environments for every team, use case or experiments through network and workload isolation
- **Intuitive Self-Service Portal**: Launch and manage VMs, containers, and networks instantly from a streamlined dashboard
- **Out of the Box Cluster**: A fully functional virtualization and cloud platform with pre-integrated services ready to host your services
- **Open Standards & RESTful APIs**: Standardized APIs that make it easy to connect, script, and scale infrastructure operations

## 💭 Getting Help/ Community

For any issues or questions during installation, connect with us via these community support channels::

1. Slack (EN) [Community][Slack-Url]
2. Discord (EN/ZH-Han) [Community][Discord-Url]
3. GitHub [Discussion](https://github.com/bigstack-oss/cubecos/discussions)
  
Please **do not** open issues which are unrelated to bugs on the [Issues](https://github.com/bigstack-oss/cubecos/issues) page.

For enterprise support, reach out to us through our [Contact Us](https://www.bigstack.co/contact-us).

For business partnerships or opportunities, connect with us via [Partners](https://www.bigstack.co/contact-form/partner).

## Development

The development environment runs CubeCOS in a containerized instance, which requires substantial memory resources to operate reliably. The following specifications apply only to the development environment’s software and hardware requirements.

For production deployments and full CubeCOS setup details, refer to the [Installation](https://docs.bigstack.co/docs/cubecos/installation/overview) section of the CubeCOS documentation.

### Hardware Requirements

- CPU
  - Architecture: x86_64
  - 8C/16T cores, 2.0 GHz or higher
  - Hardware virtualization support (Intel VT-x/ AMD-V support)
- Memory
  - Minimum: 64 GiB
- Disk
  - Minimum: 500 GiB free space

### Software Requirements

- Host operating system
  - CentOS 8
  - CentOS Stream 8
  - CentOS Stream 9
- Git
- Git LFS
- Docker (docker-ce)

### Source Code

Clone repositories with the recursive flag to include all sub-modules.

```bash
git clone --recursive git@github.com:bigstack-oss/cubecos.git
```

### Build Artifacts

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

### Troubleshoot

Other than git-lfs, make sure [hex](https://github.com/bigstack-oss/hex) (git sub-module) is properly cloned under your top source directory.

```bash
ls -lt cubecos/hex
```

## Community

Have questions or want to discuss CubeCOS development? Connect with us, check out our [Community Channels](https://www.bigstack.co/community) or start a conversation in our [Discussion](https://github.com/bigstack-oss/cubecos/discussions).

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines and architecture documentation.

- [License](./LICENSE)
- [Contributing](./CONTRIBUTING.md)
- [Code of Conduct](./CODE_OF_CONDUCT.md)
  - [Bash Convention](./doc/code_of_conduct_bash.md)
- [Security](./SECURITY.md)

To report bugs, please create an issue in our [GitHub Issues](https://github.com/bigstack-oss/cubecos/issues). Do not report security vulnerabilities via GitHub Issues.

To report security vulnerabilities, follow the steps outlined in our [Security](./SECURITY.md) policy or through [GitHub Security Reporting](https://github.com/bigstack-oss/cubecos/security/advisories/new).

## License

Copyright (c) 2025 [Bigstack co., ltd](https://bigstack.co/)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[License-Url]: https://www.apache.org/licenses/LICENSE-2.0
[License-Image]: https://img.shields.io/badge/License-Apache2-blue.svg?style=flat-square
[Slack-Image]: https://img.shields.io/discord/1372094838089977887?style=flat-square&logo=Slack
[Slack-Url]: https://join.slack.com/t/cubecos/shared_invite/zt-2yalb3gmr-rETnY7SBxlgmBw7Gxac9tA
[Discord-Image]: https://img.shields.io/discord/1372094838089977887?style=flat-square&logo=discord
[Discord-Url]: https://discord.gg/VuMX4UhEFG
[Docs-Image]: https://img.shields.io/badge/docs-view-green.svg?style=flat-square&logo=docusaurus
[Docs-Url]: https://docs.bigstack.co
[Website-Image]: https://img.shields.io/badge/web-view-blue.svg?style=flat-square
[Website-Url]: https://www.bigstack.co/
[Youtube-Image]: https://img.shields.io/youtube/views/peTSzcAueEc?style=flat-square&logo=youtube
[Youtube-Url]: https://www.youtube.com/@bigstacktech
