//go:build tailcat_ctest

package main

/*
#include <stdint.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <dlfcn.h>

typedef void (*StateCallback)(uintptr_t id, int32_t state, const char* info);
typedef void (*DataCallback)(uintptr_t id, int32_t is_binary, const uint8_t* data, int32_t len);

static const char* captured_state = NULL;
static const uint8_t* captured_data = NULL;
static int32_t captured_data_len = 0;
static atomic_int captured_state_count = 0;
static atomic_int captured_data_count = 0;

static void capture_state(uintptr_t id, int32_t state, const char* info) {
	captured_state = info;
	atomic_fetch_add(&captured_state_count, 1);
}

static void capture_data(uintptr_t id, int32_t is_binary, const uint8_t* data, int32_t len) {
	captured_data = data;
	captured_data_len = len;
	atomic_fetch_add(&captured_data_count, 1);
}

static inline StateCallback capture_state_ptr(void) { return capture_state; }
static inline DataCallback capture_data_ptr(void) { return capture_data; }
static inline void* lookup_shared_export(const char* path, const char* symbol) {
	void* handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
	if (handle == NULL) return NULL;
	void* sym = dlsym(handle, symbol);
	dlclose(handle);
	return sym;
}
static inline const char* get_captured_state(void) { return captured_state; }
static inline const uint8_t* get_captured_data(void) { return captured_data; }
static inline int32_t get_captured_data_len(void) { return captured_data_len; }
static inline int32_t get_captured_state_count(void) { return atomic_load(&captured_state_count); }
static inline int32_t get_captured_data_count(void) { return atomic_load(&captured_data_count); }
static inline void clear_captured_state(void) { captured_state = NULL; }
static inline void clear_captured_data(void) { captured_data = NULL; captured_data_len = 0; }
static inline void reset_capture(void) {
	captured_state = NULL;
	captured_data = NULL;
	captured_data_len = 0;
	atomic_store(&captured_state_count, 0);
	atomic_store(&captured_data_count, 0);
}
*/
import "C"

import "unsafe"

func installCaptureCallbacks(sess *TailcatSession) {
	sess.stateCb = C.capture_state_ptr()
	sess.dataCb = C.capture_data_ptr()
}

func resetCapture() {
	C.reset_capture()
}

func capturedStateCount() int32 {
	return int32(C.get_captured_state_count())
}

func capturedDataCount() int32 {
	return int32(C.get_captured_data_count())
}

func capturedState() string {
	p := C.get_captured_state()
	if p == nil {
		return ""
	}
	return C.GoString(p)
}

func freeCapturedState() {
	p := C.get_captured_state()
	if p != nil {
		// Free through the exported symbol, exactly as the Dart side must.
		TailcatFree(unsafe.Pointer(p))
		C.clear_captured_state()
	}
}

func capturedData() []byte {
	p := C.get_captured_data()
	if p == nil {
		return nil
	}
	return C.GoBytes(unsafe.Pointer(p), C.int(C.get_captured_data_len()))
}

func freeCapturedData() {
	p := C.get_captured_data()
	if p != nil {
		// Free through the exported symbol, exactly as the Dart side must.
		TailcatFree(unsafe.Pointer(p))
		C.clear_captured_data()
	}
}

func sharedLibraryExports(path, symbol string) bool {
	cPath := C.CString(path)
	defer C.free(unsafe.Pointer(cPath))
	cSymbol := C.CString(symbol)
	defer C.free(unsafe.Pointer(cSymbol))
	return C.lookup_shared_export(cPath, cSymbol) != nil
}

func churnCAllocations(n int) {
	for i := 0; i < n; i++ {
		q := C.CString("XXXXXXXXX")
		C.free(unsafe.Pointer(q))
	}
}

func testSend(id uintptr, isBinary int32, payload []byte) int32 {
	p := C.CBytes(payload)
	defer C.free(p)
	return TailcatSend(C.uintptr_t(id), isBinary, (*C.uint8_t)(p), int32(len(payload)))
}

func testClose(id uintptr) {
	TailcatClose(C.uintptr_t(id))
}
