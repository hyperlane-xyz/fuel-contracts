# Exit if there are ever any errors
set -e

packages_with_tests=( merkle-test bytes-extended multisig-ism-metadata-test hyperlane-message-test hyperlane-mailbox )

current_dir=$(pwd)

for package in "${packages_with_tests[@]}"
do
    echo "Running tests in package: $package"
    cd $current_dir/$package
    forc build
    forc test
    # Run Rust tests if there are any
    if [ -f Cargo.toml ]; then
        cargo test
    fi
done
