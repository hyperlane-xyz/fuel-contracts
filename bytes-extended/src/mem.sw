library mem;

/// The number of bytes in a 64-bit Fuel VM word.
const BYTES_PER_WORD: u64 = 8u64;

/// Wraps a copy type.
///
/// Types like u64, u32, u16, u8, and bool are copy types,
/// which are ordinarily kept in registers and not in memory.
///
/// Wrapping a copy type in a struct will implicitly result in the
/// type being brought into memory. This struct exists to help write
/// and read copy types to and from memory.
pub struct CopyTypeWrapper {
    value: u64,
}

impl CopyTypeWrapper {
    /// Creates a new CopyTypeWrapper with the value 0.
    fn new() -> Self {
        Self { value: 0u64 }
    }

    /// Creates a new CopyTypeWrapper from `value` that can
    /// be implicitly upcasted into u64.
    /// Note that the value property of the struct is a u64,
    /// so the stored value will be left-padded with zeroes to
    /// fit within 64 bits.
    fn with_value(value: u64) -> Self {
        Self { value }
    }

    /// Gets a pointer to where a value that is `byte_width`
    /// bytes in length starts.
    /// E.g. if the underlying value is a u16, `byte_width`
    /// should be `2`.
    fn get_ptr(self, byte_width: u64) -> raw_ptr {
        let ptr = __addr_of(self);
        // Account for the potential left-padding of the underlying value
        // to point directly to where the underlying value's contents
        // would start.
        ptr.add_uint_offset(BYTES_PER_WORD - byte_width)
    }

    /// Gets the value, implicitly casting from u64 to the desired type.
    fn value<T>(self) -> T {
        self.value
    }
}

impl CopyTypeWrapper {
    /// Writes the copy type `value` that is `byte_count` bytes in length to
    /// memory and returns a pointer to where the value starts.
    ///
    /// ### Arguments
    ///
    /// * `value` - The value to write. While this is a u64, any values whose
    ///   original type is smaller may be implicitly upcasted.
    /// * `byte_count` - The number of bytes of the original value. E.g. if the value
    ///   being written is originally a u16, this should be 2 bytes.
    pub fn ptr_to_value(value: u64, byte_count: u64) -> raw_ptr {
        // Use the wrapper struct to get a reference type for a non-reference type.
        let wrapper = Self::with_value(value);
        // Get the pointer to where the value starts within the wrapper struct.
        wrapper.get_ptr(byte_count)
    }

    /// Reads a copy type value that is `byte_count` bytes in length from `ptr`.
    ///
    /// ### Arguments
    /// * `ptr` - A pointer to memory where the value begins. The `byte_count` bytes
    ///   starting at `ptr` are read.
    /// * `byte_count` - The number of bytes of the value's type. E.g. if the value
    ///   being read is a u16, this should be 2 bytes.
    pub fn value_from_ptr<T>(ptr: raw_ptr, byte_count: u64) -> T {
        // Create a wrapper struct with a zero value.
        let wrapper = CopyTypeWrapper::new();
        // Get the pointer to where the value should be written to within the wrapper struct.
        let wrapper_ptr = wrapper.get_ptr(byte_count);
        // Copy the `byte_count` bytes from `ptr` into `wrapper_ptr`.
        ptr.copy_bytes_to(wrapper_ptr, byte_count);
        wrapper.value()
    }
}
