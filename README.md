Pull a docker image from Openconext-Containers for building the Step-up software

Host Requirements:

* Docker with Docker Compose
* An internet connection

Build a component using `stepup-build.sh <component-name>` where `<component name>` is one of: 

* Stepup-Middleware 
* Stepup-Gateway 
* Stepup-SelfService 
* Stepup-RA
* Stepup-Azure-MFA
* Stepup-Webauthn
* oath-service-php

A specific tag or banch to build can be specified using `--tag <tag name>` and  `--branch <branch name>`

`stepup-build.sh` checks out the git repositories in the Stepup-Build repository. This step is performed on the host. Next `stepup-build2.sh` is run in container for building the tarballs. When the build is successful the resulting tarball is copied to the current directory. Name format: `<component-name>-<branch or tag>-<date of last commit YYYYMMDDhhmmssZ>-<commit>.tar.bz2`. E.g. `Stepup-SelfService-develop-20150223143536Z-6ef51b629bc968218b582605894445b857927a4d.tar.bz2` 

Note: The build script will clean & reset the the git repo's it uses, any manual changes to these repo's will be lost (Stepup-Build is not affected)!
