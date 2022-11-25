packages=( hyperlane-mailbox merkle merkle-test )

current_dir=$(pwd)

for package in "${packages[@]}"
do
    echo "Building package: $package"
	cd $current_dir/$package && forc fmt && forc build
done
