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

#[test()]
fn test_expect_ok() {
    let inner = 12345;
    assert(inner == Result::<u64, u64>::Ok(inner).expect("foo"));
}

// We don't have access to the exact revert message in Sway tests.
#[test(should_revert)]
fn test_expect_none() {
    let _ = Result::<u64, u64>::Err(123).expect("foo");
}
