packages_with_tests=( merkle-test hyperlane-message-test hyperlane-mailbox )

current_dir=$(pwd)

for package in "${packages_with_tests[@]}"
do
    echo "Running tests in package: $package"
    cd $current_dir/$package && forc build && cargo test
done
