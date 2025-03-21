#!/bin/bash

# Get the path to the git hooks directory
HOOK_DIR="$(git rev-parse --show-toplevel)/.git/hooks"
HOOK_PATH="$HOOK_DIR/pre-commit"
LINTER_SCRIPT_PATH="lint.sh"

install_hook() {
	# Remove any pre-commit hook that might already be installed
	rm -f "${HOOK_PATH}"

	# Define the hook
	cat > "${HOOK_PATH}" <<- EOF
	#!/bin/sh

	# Run the linter script
	sh $LINTER_SCRIPT_PATH --fix

	git add -u
	echo 'SwiftLint finished fixing files. Proceeding with commit...'
	EOF

	# Make the file executable
	chmod +x "$HOOK_PATH"

	echo "Pre-commit hook installed successfully!"
}

uninstall_hook() {
	# Remove the pre-commit hook if it exists
	if [ -f "$HOOK_PATH" ]; then
		rm "$HOOK_PATH"
		echo "Pre-commit hook uninstalled successfully!"
	else
		echo "No pre-commit hook found to uninstall."
	fi
}

# Check command-line options
if [ "$1" == "--install" ]; then
	install_hook
elif [ "$1" == "--uninstall" ]; then
	uninstall_hook
else
	echo "Usage: $0 --install | --uninstall"
	exit 1
fi