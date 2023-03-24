library result;

struct ResultErrRevert<M, E> {
    message: M,
    error: E,
}

impl<T, E> Result<T, E> {
    pub fn expect<M>(self, message: M) -> T {
        match self {
            Result::Ok(inner) => inner,
            Result::Err(err) => {
                // Revert with the message.
                // The `revert` function only accepts u64, so as
                // a workaround we use require.
                require(false, ResultErrRevert {
                    message,
                    error: err,
                });
                // Trick the compiler into knowing that the branch
                // will revert and doesn't need to have the same return
                // type as Option::Some
                revert(0);
            }
        }
    }
}
