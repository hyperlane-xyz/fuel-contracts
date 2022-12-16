library mem;

pub fn alloc_stack_word() -> raw_ptr {
    asm(ptr) {
        move ptr sp; // Copy the stack pointer (sp) register into `ptr`.
        cfei i8; // Add 8 bytes (1 word) to the stack pointer, giving the memory at `ptr` a size of 8 bytes.
        ptr: raw_ptr // Return `ptr`.
    }
}
