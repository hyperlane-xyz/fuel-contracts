packages=( merkle merkle-test hyperlane-message hyperlane-message-test hyperlane-mailbox )

current_dir=$(pwd)

for package in "${packages[@]}"
do
    echo "Building package: $package"
    cd $current_dir/$package && forc fmt && forc build
done
