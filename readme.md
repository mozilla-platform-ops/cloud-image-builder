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

### commit message syntax for ci instructions

#### the list of images to build and/or deploy can be controlled with commit message syntax.

instructions are processed when they are included on their own new line within the commit message. supported instructions include:
- `no-ci`: skips all ci tasks
- `pool-deploy`: skips both disk-image and machine-image builds and only updates worker-manager with whatever images were most recently built
- key filter-types (cloud-image-builder os configurations):
  - `include keys: win2012, win10-64-gpu`: build and deploy only images whose configuration is included in [config/win2012.yaml](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/config/win2012.yaml) or [config/win10-64-gpu.yaml](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/config/win10-64-gpu.yaml)
  - `exclude keys: win7-32, win2019`: build and deploy **all** images **except** those whose configuration is included in [config/win7-32.yaml](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/config/win7-32.yaml) or [config/win2019.yaml](https://github.com/mozilla-platform-ops/cloud-image-builder/blob/master/config/win2019.yaml)
- pool filter-types (worker-manager pools):
  - `include pools: gecko-1/win2012-azure, gecko-t/win7-32-gpu-azure`: build and deploy only images whose configured worker-pool target is either gecko-1/win2012-azure or gecko-t/win7-32-gpu-azure
  - `exclude pools: gecko-3/win2012-azure, gecko-t/win10-64-gpu-azure` build and deploy **all** images **except** those whose configured worker-pool target is either gecko-3/win2012-azure or gecko-t/win10-64-gpu-azure
- region filter-types (cloud regions):
  - `include pools: northcentralus, westus` build and deploy **all** images whose configured regional target is either northcentralus or westus
  - `exclude pools: eastus, southcentralus` build and deploy **all** images **except** those whose configured regional target is either eastus or southcentralus

#### combining instructions

- the no-ci instruction causes all other instructions to be ignored
- the pool-deploy instruction and the pool and region filter-types can be combined 
- key and pool filter-types **cannot** be combined
- include and exclude filters of the same filter-type **cannot** be combined
- key and region filter-types **can** be combined
- pool and region filter-types **can** be combined

#### some examples using commit syntax include:

```bash
git commit \
  -m "bug 123456 - patch a windows 10 security vulnerability" \
  -m "update network drivers and rebuild disk/machine images" \
  -m "include keys: win10-64, win10-64-gpu"
git push origin master
```

```bash
git commit \
  -m "bug 654321 - redeploy gpu tester pools to cheaper regions" \
  -m "use existing images in northcentralus, westus2 and centralus" \
  -m "pool-deploy" \
  -m "include pools: gecko-t/win7-32-gpu-azure, gecko-t/win10-64-gpu-azure" \
  -m "include regions: northcentralus, westus2, centralus"
git push origin master
```

```bash
sed -i -e 's/StackdriverLogging-v1-8.exe/StackdriverLogging-v1-9.exe/g' \
  config/packages.yaml
git add config/packages.yaml
git commit -m "bug 987654 - update stackdriver everywhere"
git push origin master
```