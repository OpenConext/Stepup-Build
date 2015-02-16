Create a Centos 6.5 VM using Vagrant for building the Step-up software
Provisioning of the VM through Ansible

Host Requirements:

* Vagrant
* virtual box, or another provider supported by vagrant
* Ansible

Create the VM, from the root for the repo run:

`varant up --provider=virtualbox`
 (or `varant up --provider=vmware_fusion`)

To rerun just the ansible provisioning: `vagrant provision`


Build a component using `stepup-build.sh <component-name>` where `<component name>` is one of: 

* Stepup-Middleware 
* Stepup-Gateway 
* Stepup-SelfService 
* Stepup-RA

Start the script from the root of the Stepup-Build repo, starting the script from other directories is not supported and will probably fail.

A specific tag or banch to build can be specified using `--tag <tag name>` and  `--branch <branch name>`

`stepup-build.sh` checks out the git repositories relative to the current working directory. This step is performed on the host. Next `stepup-build2.sh` is run in the Vargant VM for building the tarballs.

Note: The build script will clean & reset the the git repo's it uses, any manual changes to these repo's will be lost!