// Mithka: the only declarations the console logger used from the former
// bindgen output of wrapper.h, written out so builds need no libclang.
#![allow(non_upper_case_globals)]
#![allow(dead_code)]

use std::os::raw::{c_char, c_int, c_uint};

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub const ASL_LEVEL_NOTICE: c_uint = 5;

#[cfg(any(target_os = "ios", target_os = "macos"))]
unsafe extern "C" {
    pub fn asl_log(
        client: *mut std::os::raw::c_void,
        msg: *mut std::os::raw::c_void,
        level: c_int,
        format: *const c_char,
        ...
    ) -> c_int;
}

#[cfg(target_os = "android")]
pub const android_LogPriority_ANDROID_LOG_VERBOSE: c_uint = 2;

#[cfg(target_os = "android")]
unsafe extern "C" {
    pub fn __android_log_print(prio: c_int, tag: *const c_char, fmt: *const c_char, ...) -> c_int;
}
