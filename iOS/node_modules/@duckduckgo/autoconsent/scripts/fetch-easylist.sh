#!/bin/bash
set -e

SCRIPT_DIR="`dirname $0`"
RULES_DIR="${SCRIPT_DIR}/../rules/filterlists/"

# set EASYLIST_REVISION to a specific commit hash to lock to a specific revision. By default we use the latest revision.
if [ "${EASYLIST_REVISION}" = "" ];
then
    echo "Looking up the latest Easylist revision..."
    EASYLIST_REVISION=`git ls-remote https://github.com/easylist/easylist.git refs/heads/master | cut -f 1`
fi

echo "Using Easylist revision: ${EASYLIST_REVISION}"

rm -f rules/filterlists/easylist_cookie_*
wget --directory-prefix="${RULES_DIR}" \
    "https://raw.githubusercontent.com/easylist/easylist/${EASYLIST_REVISION}/easylist_cookie/easylist_cookie_general_hide.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/${EASYLIST_REVISION}/easylist_cookie/easylist_cookie_specific_hide.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/${EASYLIST_REVISION}/easylist_cookie/easylist_cookie_specific_uBO.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/${EASYLIST_REVISION}/easylist_cookie/easylist_cookie_international_specific_hide.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/${EASYLIST_REVISION}/easylist_cookie/easylist_cookie_allowlist_general_hide.txt"

echo "${EASYLIST_REVISION}" > "${RULES_DIR}/easylist_revision.txt"
echo "Saved the Easylist revision to ${RULES_DIR}/easylist_revision.txt"
