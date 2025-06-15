# CubeCOS (Cube Cloud Operating System)

<div align="center">
<br/>
<br/>
<p align="center">
  <img width="234" alt="cubecos logo full" src="doc/media/logo-blue.png"/>
</p>

[![License][License-Image]][License-Url] [![Slack][Slack-Image]][Slack-Url] [![Discord][Discord-Image]][Discord-Url] [![Docs][Docs-Image]][Docs-Url] [![Website][Website-Image]][Website-Url] [![Youtube][Youtube-Image]][Youtube-Url]

</div>

CubeCOS is a unified cloud operating system that integrates storage, compute, and networking into a single image. Deploy CubeCOS to deliver a public cloud–like experience within your own on-premise infrastructure.

Designed for organizations that need cloud flexibility without compromising control, CubeCOS offers:

- Multi-tenancy with robust isolation between workloads
- Self-service IT portal empowering teams to provision resources on demand
- Cloud native architecture supporting modern application development

Deploy your own private cloud infrastructure with the simplicity of public cloud.

Join us in building the future of software-defined infrastructure!

## Development

### Hardware & OS Requirements

- CPU
  - Architecture: x86_64
  - At least Intel(R) Xeon(R) Silver 4210
- Memory
  - At least 64 GiB
- Disk
  - At least 100 GiB free space
- OS
  - CentOS 8
  - CentOS Stream 8
  - CentOS Stream 9

### Dev Tools

- git
- git lfs
- docker (docker-ce)

### Source Code

Clone repositories with the recursive flag to include sub-modules.

```bash
git clone --recursive git@github.com:bigstack-oss/cubecos.git
```

### Build Artifacts

1. Create and enter jail

default PROJECT="centos9-jail"

```bash
cd cubecos
make [PROJECT=XXX] centos9-jail enter
```

Without specifying the project name, `make centos9-jail` would create the build folder and the container with the default name "centos9-jail".

After creating the build jail, under the parent directory of folder cubecos, there would be two folders, one is the `cubecos`, and the other one would be the build folder, which is default to `centos9-jail`.

```bash
cubecos> ls ..
cubecos centos9-jail
```

`make PROJECT=example centos9-jail` would create another jail named `example`, and the build folder would be `example` under the parent directory of folder cubecos

```bash
cubecos> ls ..
cubecos centos9-jail example
```

We could use the command `make enter` to enter the default build jail `centos9-jail`. Alternatively, `make PROJECT=example enter` would bring us into the build jail `example`.

2. Build various CubeCOS install media

Install media: ISO, USB, PXE, full, etc., where full is everything.

```bash
[root@centos9-jail centos9-jail]# make usb
```

```bash
# all
make full

# usb
make usb

# iso
make iso
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

## Installation

Please follow the guidelines presented on [Bigstack Documentation - CubeCOS - Quick Start - Overview](https://docs.bigstack.co/docs/cubecos/quick-start/overview) to install and set up CubeCOS.

Official images could be found on [Releases](https://github.com/bigstack-oss/cubecos/releases).

If any difficulty is encountered during the installation, please reach out to our [Discussion](https://github.com/bigstack-oss/cubecos/discussions). Please do not open issues which are unrelated to bugs on page [Issue](https://github.com/bigstack-oss/cubecos/issues).

Further inquiries regarding the support, including operations and maintenances, please contact us through [Contact Us](https://www.bigstack.co/contact-us).

For business collaborations, please contact us [Bigstack](https://www.bigstack.co/contact-form/sales) or our partners [Partners](https://www.bigstack.co/contact-form/partner).

## Community

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines and architecture documentation.

- [License](./LICENSE)
- [Contributing](./CONTRIBUTING.md)
- [Code of Conduct](./CODE_OF_CONDUCT.md)
  - [Bash Convention](./doc/code_of_conduct_bash.md)
- [Security](./SECURITY.md)

If having any general questions, including questions related to developing CubeCOS, please reach out to our [Discussion](https://github.com/bigstack-oss/cubecos/discussions).

To report bugs, please raise the issue through [Issue](https://github.com/bigstack-oss/cubecos/issues). Please only open issues related to bugs. General questions and feature requests are recommended to be started on [Discussion](https://github.com/bigstack-oss/cubecos/discussions). Please do not open issues regarding security vulnerabilities on page [Issue](https://github.com/bigstack-oss/cubecos/issues).

To report security vulnerabilities, please follow [Security](./SECURITY.md).

To join our Slack, Discord, and follow our GitHub, please check out [Community Channels](https://www.bigstack.co/community).

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
