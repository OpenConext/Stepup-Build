Create a Centos 7.0 VM using Vagrant for building the Step-up software
Provisioning of the VM through Ansible

Host Requirements:

* Vagrant
* virtual box, or another provider supported by vagrant
* Ansible 1.8 or newer

Create the VM, from the root for the repo run:

`varant up --provider=virtualbox`
 (or `varant up --provider=vmware_fusion`)

To rerun just the ansible provisioning: `vagrant provision`


Build a component using `stepup-build.sh <component-name>` where `<component name>` is one of: 

* Stepup-Middleware 
* Stepup-Gateway 
* Stepup-SelfService 
* Stepup-RA
* Stepup-tiqr
* oath-service-php

A specific tag or banch to build can be specified using `--tag <tag name>` and  `--branch <branch name>`

`stepup-build.sh` checks out the git repositories in the Stepup-Build repository. This step is performed on the host. Next `stepup-build2.sh` is run in the Vargant VM for building the tarballs. When the build is successfull the resulting tarball is copied to the current directory. Name format: `<component-name>-<branch or tag>-<date of last commit YYYYMMDDhhmmssZ>-<commit>.tar.bz2`. E.g. `Stepup-SelfService-develop-20150223143536Z-6ef51b629bc968218b582605894445b857927a4d.tar.bz2`

Note: The build script will clean & reset the the git repo's it uses, any manual changes to these repo's will be lost (Stepup-Build is not affected)!
