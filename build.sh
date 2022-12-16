packages=( merkle merkle-test bytes-extended hyperlane-message hyperlane-message-test ownership hyperlane-mailbox )

current_dir=$(pwd)

for package in "${packages[@]}"
do
    echo "Building package: $package"
    cd $current_dir/$package && forc fmt && forc build
done
