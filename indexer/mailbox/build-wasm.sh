# Can be ran from any directory within the workspace

if ! command -v wasm-snip &> /dev/null; then
    echo "wasm-snip could not be found, did you install it?"
    exit 1
fi

ENVIRONMENT_VARS=""

# If this exists, assume `brew install llvm` was ran and
# we should set the AR and CC environment variables as needed.
# See https://fuellabs.github.io/fuel-indexer/master/components/assets/module.html#notes-on-wasm
# for details
if [ -f /opt/homebrew/opt/llvm/bin/llvm-ar ]; then
    export AR=/opt/homebrew/opt/llvm/bin/llvm-ar
    export CC=/opt/homebrew/opt/llvm/bin/clang
fi

set -e

CARGO_WORKSPACE_ROOT_DIR=$(dirname -- $(cargo locate-project -q --workspace --message-format plain))

echo "pwd" $(pwd)


# Builds the wasm, and snips bad wasm.
# See https://fuellabs.github.io/fuel-indexer/master/getting-started/application-dependencies/wasm-snip.html
cargo build -p mailbox-indexer --release --target wasm32-unknown-unknown &&
    wasm-snip $CARGO_WORKSPACE_ROOT_DIR/target/wasm32-unknown-unknown/release/mailbox_indexer.wasm -o $CARGO_WORKSPACE_ROOT_DIR/target/wasm32-unknown-unknown/release/mailbox_indexer.wasm -p __wbindgen

set +e
