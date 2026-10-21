#!/bin/bash

delete_data() {
    bundle_id="$1"

    echo "Deleting data for ${bundle_id}"

    if defaults read "${bundle_id}" &>/dev/null; then
        defaults delete "${bundle_id}"
    fi

    data_path="${HOME}/Library/Containers/${bundle_id}/Data"
    if [[ -d "${data_path}" ]]; then
        printf '%s' "    Deleting ${data_path} ... "
        rm -r "${data_path}" || { echo "❌"; exit 1; }
        echo "✅"
    else
        echo "    Nothing to do for ${data_path}"
    fi

    if [[ -n "${clear_webkit_dir}" ]]; then
        webkit_dir="${HOME}/Library/WebKit/${bundle_id}"
        if [[ -d "${webkit_dir}" ]]; then
            printf '%s' "    Deleting ${webkit_dir} ... "
            rm -r "${webkit_dir}" || { echo "❌"; exit 1; }
            echo "✅"
        else
            echo "    Nothing to do for ${webkit_dir}"
        fi
    fi
}

bundle_id=
config_id=

case "$1" in
    debug)
        bundle_id="com.duckduckgo.macos.browser.debug"
        config_ids="*com.duckduckgo.macos.browser.app-configuration.debug"
        netp_bundle_ids_glob="*com.duckduckgo.macos.browser.network-protection*debug"
        clear_webkit_dir=1
        ;;
    review)
        bundle_id="com.duckduckgo.macos.browser.review"
        config_ids="*com.duckduckgo.macos.browser.app-configuration.review"
        netp_bundle_ids_glob="*com.duckduckgo.macos.browser.network-protection*review"
        clear_webkit_dir=1
        ;;
    alpha)
        bundle_id="com.duckduckgo.macos.browser.alpha"
        config_ids="*com.duckduckgo.macos.browser.app-configuration.alpha"
        netp_bundle_ids_glob="*com.duckduckgo.macos.browser.network-protection*alpha"
        clear_webkit_dir=1
        ;;
    debug-appstore)
        bundle_id="com.duckduckgo.mobile.ios.debug"
        config_ids="*com.duckduckgo.mobile.ios.app-configuration.debug"
        ;;
    review-appstore)
        bundle_id="com.duckduckgo.mobile.ios.review"
        config_ids="*com.duckduckgo.mobile.ios.app-configuration.review"
        ;;
    alpha-appstore)
        bundle_id="com.duckduckgo.mobile.ios.alpha"
        config_ids="*com.duckduckgo.mobile.ios.app-configuration.alpha"
        ;;
    *)
        echo "usage: clean-app debug|review|alpha|debug-appstore|review-appstore|alpha-appstore"
        exit 1
        ;;
esac

delete_data "${bundle_id}"

# shellcheck disable=SC2046
read -r -a config_bundle_ids <<< $(
    find "${HOME}/Library/Group Containers/" \
        -type d \
        -maxdepth 1 \
        -name "${config_ids}" \
        -exec basename {} \;
)
for config_id in "${config_bundle_ids[@]}"; do
    echo "Deleting config data for ${config_id}"
    path="${HOME}/Library/Group Containers/${config_id}"
    if [[ -d "${path}" ]]; then
        printf '%s' "    Deleting ${path} ... "
        rm -r "${path}" || { echo "❌"; exit 1; }
        echo "✅"
    else
        echo "    Nothing to do for ${path}"
    fi

done

if [[ -n "${netp_bundle_ids_glob}" ]]; then
    # shellcheck disable=SC2046
    read -r -a netp_bundle_ids <<< $(
        find "${HOME}/Library/Containers/" \
            -type d \
            -maxdepth 1 \
            -name "${netp_bundle_ids_glob}" \
            -exec basename {} \;
    )
    for netp_bundle_id in "${netp_bundle_ids[@]}"; do
        delete_data "${netp_bundle_id}"
    done
fi
