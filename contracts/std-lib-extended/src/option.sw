library;

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

#[test()]
fn test_expect_some() {
    let inner = 12345;
    assert(inner == Option::Some(inner).expect("foo"));
}

// We don't have access to the exact revert message in Sway tests.
#[test(should_revert)]
fn test_expect_none() {
    let _ = Option::<u64>::None.expect("foo");
}
