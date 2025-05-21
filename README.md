# CubeCOS (Cube Cloud Operating System)

[![License][License-Image]][License-Url] [![Slack][Slack-Image]][Slack-Url] [![Discord][Discord-Image]][Discord-Url] [![Docs][Docs-Image]][Docs-Url] [![Website][Website-Image]][Website-Url] [![Youtube][Youtube-Image]][Youtube-Url]

A software-defined private cloud platform that integrates storage, compute, and networking resources. CubeCOS is a comprehensive cloud solution that seamlessly integrates storage, computing, and networking into a single software package.

Built for organizations seeking cloud flexibility with complete control, CubeCOS delivers:

- Multi-tenancy with robust isolation between workloads
- Self-service IT portal empowering teams to provision resources on demand
- Cloud native architecture supporting modern application development

Deploy your own private cloud infrastructure with the simplicity of public cloud.

Join our community to help build the future of software-defined infrastructure!

## Prerequisites

1. Install git and git-lfs

```bash
sudo apt-get install git git-lfs
git lfs install
```

2. Clone repos with the recursive flag to include sub-modules

```bash
git clone --recursive git@github.com:bigstack-oss/cubecos.git
```

## Build Images

1. Create and enter jail (default PROJECT="centos9-jail")

```bash
cd cubecos
make [PROJECT=XXX] centos9-jail enter
```

2. Build various Cube install media (ISO, USB, PXE, full, etc.) where full is everything

```bash
[root@centos9-jail centos9-jail]# make usb
```

### Troubleshoot

Other than git-lfs, make sure [hex](https://github.com/bigstack-oss/hex) (git sub-module) is properly cloned under your top source directory.

```bash
ls -lt cubecos/hex
```

## Development

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines and architecture documentation.

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
