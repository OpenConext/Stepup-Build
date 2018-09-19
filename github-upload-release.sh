#!/bin/bash

# Create a release on github for a component built with stepup-build and upload the component to github
# Requires a github API key:
# 1) Go to: https://github.com/settings/tokens
# 2) Create an access token with scope "public_repo"
# 3) Store the access token in a file named "~/.github-access-token"

# If upload fails with: HTTP 422 {"message":"Validation Failed" ... ,"errors":[{"resource":"ReleaseAsset","code":"already_exists","field":"name"}]}
# Then:
# 1) Go the release in github
# 2) Choose "Edit Release"
# 3) Delete the failing asset
# 4) Choose "Update release"

CWD=`pwd`
BASEDIR=`dirname $0`
COMPONENTS=("Stepup-Middleware" "Stepup-Gateway" "Stepup-SelfService" "Stepup-RA" "Stepup-tiqr" "oath-service-php" "Stepup-irma")

function error_exit {
    echo "${1}"
    if [ -n "${TMP_FILE}" -a -d "${TMP_FILE}" ]; then
        rm "${TMP_FILE}"
    fi
    cd ${CWD}
    exit 1
}

# Process options
COMPONENT_TARBALL=$1
if [ -z "${COMPONENT_TARBALL}"  ]; then
    echo "Usage: $0 <component tarball>"
    exit 1;
fi

if [ ! -f "${COMPONENT_TARBALL}" ]; then
    error_exit "File not found: '${COMPONENT_TARBALL}'"
fi


component_tarball_basename=`basename ${COMPONENT_TARBALL}`
found=0
for comp in "${COMPONENTS[@]}"; do
    regex="^($comp).*(\.tar\.bz2)$"
    if [[ $component_tarball_basename =~ $regex ]]; then
        found=1
        COMPONENT=$comp
    fi
done
if [ "$found" -ne "1" ]; then
    error_exit "Tarball to deploy must end in .tar.bz2 and start with one of: ${COMPONENTS[*]}"
fi

# Get absolute path to component tarball
cd ${CWD}
cd `dirname ${COMPONENT_TARBALL}`
COMPONENT_TARBALL=`pwd`/`basename ${COMPONENT_TARBALL}`
cd ${CWD}

# Cut commit hash from tarball
regex="^${COMPONENT}-(.*)-([0-9]{14}Z)-([0-9a-f]{40})\.tar\.bz2$"
if [[ ! $component_tarball_basename =~ $regex ]]; then
   error_exit "Tarball name must have format: ${COMPONENT}-tag_or_branch-commit_date-commit_sha1.tar.bz2"
fi

tag_branch=${BASH_REMATCH[1]}
commit_time=${BASH_REMATCH[2]}
commit_sha1=${BASH_REMATCH[3]}

# Tag to use for publishing release
githubtag=${tag_branch}-${commit_time}-${commit_sha1}

githubrepo="OpenConext/${COMPONENT}"

echo "Path to tarball: ${COMPONENT_TARBALL}"
echo "Component full: ${component_tarball_basename}"
echo "Component: ${COMPONENT}"
echo "Tag or Branch: ${tag_branch}"
echo "Commit time: ${commit_time}"
echo "Commit SHA1: ${commit_sha1}"
echo "Github tag: ${githubtag}"
echo "Github repo: ${githubrepo}"
echo


if [ ! -f ~/.github-access-token ]; then
    error_exit "You need an github access token to authenticate to github. Create one at 'https://github.com/settings/tokens' with scope 'repo' or 'public_repo'. Store the token in '~/.github-access-token'"
fi
github_token=`cat ~/.github-access-token`



TMP_FILE=`mktemp -t github-upload`
if [ $? -ne "0" ]; then
    error_exit "Could not create temp file"
fi

echo "Checking github for release with tag '${githubtag}' in '${githubrepo}'"
http_response=`curl --write-out %{http_code} --silent --output ${TMP_FILE} https://api.github.com/repos/${githubrepo}/releases/tags/${githubtag}`
res=$?

if [ "${res}" -ne 0 ]; then
    error_exit "Problem accessing github"
fi

if [ "${http_response}" -ne "404" -a "${http_response}" -ne "200" ]; then
    error_exit "Unexpected HTTP response: ${http_response}"
fi

if [ "${http_response}" -ne "200" ]; then
    rm $TMP_FILE
    echo "Creating release with tag '${githubtag}' in '${githubrepo}'"
    json="{\"tag_name\": \"${githubtag}\", \"target_commitish\": \"${commit_sha1}\", \"name\": \"${githubtag}\", \"body\": \"\", \"draft\": false, \"prerelease\": true}"
    http_response=`curl --write-out %{http_code} --silent --output "${TMP_FILE}" --data "${json}" https://api.github.com/repos/${githubrepo}/releases?access_token=${github_token}`
    res=$?
    if [ "${res}" -ne 0 ]; then
        error_exit "Problem accessing github"
    fi
    if [ "${http_response}" -ne "201" ]; then
        cat ${TMP_FILE}; echo
        error_exit "Unexpected HTTP response: ${http_response}"
    fi
    echo "Created release"
else
    echo "Release already exists"
fi

# Parse release ID from received json using bash JSON parser from https://github.com/dominictarr/JSON.sh
release_id=`cat $TMP_FILE | ${BASEDIR}/JSON.sh/JSON.sh | grep '^\["id"\]' | cut -f2`

echo "Github release id: ${release_id}"

#cat $TMP_FILE

# Check whether file with given name was already uploaded
asset_check=`cat $TMP_FILE | ${BASEDIR}/JSON.sh/JSON.sh | grep -c "^\[\"assets\",[0-9],\"name\"\].*${component_tarball_basename}"`
if [ "${asset_check}" -gt "0" ]; then
    echo "Asset with name '${component_tarball_basename}' already present. Nothing to do."
    rm $TMP_FILE
    exit 0;
fi

echo "Uploading ${component_tarball_basename}"
rm $TMP_FILE
http_response=`curl  --progress-bar --write-out %{http_code}  --output "${TMP_FILE}" -H "Content-Type: application/x-bzip2" --data-binary "@${COMPONENT_TARBALL}" "https://uploads.github.com/repos/${githubrepo}/releases/${release_id}/assets?name=${component_tarball_basename}&access_token=${github_token}"`
res=$?
if [ "${res}" -ne 0 ]; then
    error_exit "Problem accessing github"
fi
if [ "${http_response}" -ne "201" ]; then
    cat ${TMP_FILE}; echo
    cat <<HELP
    It is safe to try again...
    If the upload fails with:
    HTTP 422 {"message":"Validation Failed" ... ,"errors":[{"resource":"ReleaseAsset","code":"already_exists","field":"name"}]}
    1) Go the release in github
    2) Choose "Edit Release"
    3) Delete the failing asset
    4) Choose "Update release"
    5) Try again
HELP
    error_exit "Unexpected HTTP response: ${http_response}"
fi
echo "Uploaded tarball"
echo -n "Download URL: "
cat $TMP_FILE | ${BASEDIR}/JSON.sh/JSON.sh | grep '^\["browser_download_url"\]' | cut -f2


rm $TMP_FILE

exit 0;
