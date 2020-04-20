# cloud image builder
## build windows cloud images from iso files
### as part of a continuous integration and deployment cycle

[![Deploy status](https://firefox-ci-tc.services.mozilla.com/api/github/v1/repository/mozilla-platform-ops/cloud-image-builder/master/badge.svg)](https://firefox-ci-tc.services.mozilla.com/api/github/v1/repository/mozilla-platform-ops/cloud-image-builder/master/latest)
[![travis build status](https://travis-ci.org/mozilla-platform-ops/cloud-image-builder.svg?branch=master)](https://travis-ci.org/mozilla-platform-ops/cloud-image-builder)

### what's going on here?
this repository stores configuration and code that is continuously integrated by taskcluster and travis tasks.

commits to the master branch result in the following actions:
- travis checks if the taskcluster [worker pools](https://github.com/mozilla-platform-ops/cloud-image-builder/tree/master/ci/config/worker-pool/relops) and [roles](https://github.com/mozilla-platform-ops/cloud-image-builder/tree/master/ci/config/role) required to do image builds under taskcluster are available and updates them if so or creates them if not.
- the taskcluster [decision task](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/ci/create-image-build-tasks.py) decides what image configurations to build and what maintenance tasks to run.
  - [purge-azure-resources](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/ci/purge-azure-resources.py) looks for azure resources that can be deleted. these include:
    - virtual machines that have been deallocated
    - network interfaces that are not associated with a virtualmachine
    - public ip address objects that have no associated ip address
    - disks that are not associated with a virtual machine
  - [build-disk-image](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/build-disk-image.ps1) performs the conversion of iso files to vhd files
    - these tasks only run if the **disk** image configuration has changed which is determined by:
      - changes to the `image` section of the yml config
      - changes to the `iso` section of the yml config
      - changes to the shared `disable-windows-service`, `drivers`, `packages`, `product-keys` and `unattend-commands` sysprep yml configs. these configurations install low level drivers, cloud-platform-agents and logging utilities that are required by the subsequent bootstrap processes and workflows
    - if a disk image build is deemed necessary because of detected changes, the commit sha of the cloud-image-builder repository at the time of the determination is appended to the image name of the built image
  - [build-machine-image](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/build-machine-image.ps1):
    - these tasks only run if the **machine** image configuration has changed which is determined by:
      - changes to the `bootstrap` section of the yml config
      - changes to the `tag` section of the yml config
    - imports the most recently built disk image to the cloud platform
    - instantiates an instance with the disk image attached as the primary/boot disk
    - triggers the configured bootstrap sequence from the yml config and waits for a successful completion of the same
    - shuts down the instance and captures a machine image from it
  - [tag-machine-images](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/ci/tag-machine-images.ps1) appends tags to new machine images with metadata specific to the image
