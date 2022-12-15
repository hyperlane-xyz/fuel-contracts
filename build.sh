current_dir=$(pwd)

for package in */
do
    echo "Building package: $package"
    cd $current_dir/$package && forc fmt && forc build
done
