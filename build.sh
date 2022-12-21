# Exit if there are ever any errors
set -e

packages=( merkle merkle-test bytes-extended multisig-ism-metadata multisig-ism-metadata-test hyperlane-message hyperlane-message-test hyperlane-mailbox )

current_dir=$(pwd)

for package in "${packages[@]}"
do
    echo "Building package: $package"
    cd $current_dir/$package && forc fmt && forc build
    # Format Rust code if there is any
    if [ -f Cargo.toml ]; then
        cargo fmt
    fi
done
