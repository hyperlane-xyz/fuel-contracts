library option;

impl<T> Option<T> {
    pub fn expect<M>(self, message: M) -> T {
        match self {
            Option::Some(inner) => inner,
            Option::None => {
                // Revert with the message.
                // The `revert` function only accepts u64, so as
                // a workaround we use require.
                require(false, message);
                // Trick the compiler into knowing that the branch
                // will revert and doesn't need to have the same return
                // type as Option::Some
                revert(0);
            }
        }
    }
}
