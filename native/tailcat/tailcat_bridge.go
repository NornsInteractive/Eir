package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef void (*DataCallback)(uintptr_t id, int32_t is_binary, const uint8_t* data, int32_t len);
typedef void (*StateCallback)(uintptr_t id, int32_t state, const char* info);

static inline void invoke_data_cb(DataCallback cb, uintptr_t id, int32_t is_binary, const uint8_t* data, int32_t len) {
    if (cb) cb(id, is_binary, data, len);
}

static inline void invoke_state_cb(StateCallback cb, uintptr_t id, int32_t state, const char* info) {
    if (cb) cb(id, state, info);
}
*/
import "C"

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	"github.com/tailscale/tailcat"
)

type TailcatSession struct {
	id       uintptr
	server   *tailcat.Server
	client   *tailcat.Client
	listener net.Listener
	conn     net.Conn
	cancel   context.CancelFunc
	isServer bool
	addr     string
	dataCb   C.DataCallback
	stateCb  C.StateCallback
	closed   atomic.Bool
	wg       sync.WaitGroup
	sendMu   sync.Mutex
	connMu   sync.Mutex
	cbMu     sync.RWMutex
	cbClosed bool
}

var (
	sessionMap sync.Map
	nextID     uintptr
)

// TailcatFree releases a buffer that this library allocated with C.CString or
// C.CBytes (state/data callback payloads and the TailcatStartServer address).
// Dart must free those buffers through this entry point so allocation and
// deallocation happen in the same C runtime heap. On Windows a Dart-side
// calloc.free would use a different heap and corrupt memory.
//
//export TailcatFree
func TailcatFree(ptr unsafe.Pointer) {
	C.free(ptr)
}

func (sess *TailcatSession) invokeState(state int32, info string) {
	sess.cbMu.RLock()
	defer sess.cbMu.RUnlock()
	if sess.cbClosed || sess.stateCb == nil || sess.closed.Load() {
		return
	}
	cInfo := C.CString(info)
	if cInfo == nil {
		return
	}
	C.invoke_state_cb(sess.stateCb, C.uintptr_t(sess.id), C.int32_t(state), cInfo)
}

func (sess *TailcatSession) invokeData(isBinary int32, data []byte) {
	if len(data) == 0 {
		return
	}
	sess.cbMu.RLock()
	defer sess.cbMu.RUnlock()
	if sess.cbClosed || sess.dataCb == nil || sess.closed.Load() {
		return
	}
	cBuf := C.CBytes(data)
	if cBuf == nil {
		return
	}
	C.invoke_data_cb(sess.dataCb, C.uintptr_t(sess.id), C.int32_t(isBinary), (*C.uint8_t)(cBuf), C.int32_t(len(data)))
}

func (sess *TailcatSession) setConn(conn net.Conn) bool {
	sess.connMu.Lock()
	defer sess.connMu.Unlock()
	if sess.closed.Load() {
		_ = conn.Close()
		return false
	}
	sess.conn = conn
	return true
}

func writeFull(w io.Writer, p []byte) error {
	for len(p) > 0 {
		n, err := w.Write(p)
		if n > 0 {
			p = p[n:]
		}
		if err != nil {
			return err
		}
		if n == 0 {
			return io.ErrShortWrite
		}
	}
	return nil
}

func readLoop(sess *TailcatSession, conn net.Conn) {
	defer func() {
		if !sess.closed.Load() {
			sess.invokeState(2, "disconnected")
		}
	}()

	hdr := make([]byte, 5)
	for {
		if sess.closed.Load() {
			return
		}
		if _, err := io.ReadFull(conn, hdr); err != nil {
			return
		}
		dataLen := binary.BigEndian.Uint32(hdr[0:4])
		isBinary := int32(hdr[4])

		if dataLen > 10*1024*1024 { // max 10MB frame
			return
		}

		buf := make([]byte, dataLen)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}

		sess.invokeData(isBinary, buf)
	}
}

//export TailcatStartServer
func TailcatStartServer(dataCb C.DataCallback, stateCb C.StateCallback) (*C.char, C.uintptr_t) {
	ctx, cancel := context.WithCancel(context.Background())
	srv := &tailcat.Server{}
	ln, err := srv.Listen(ctx, "tcp", ":0")
	if err != nil {
		cancel()
		return C.CString(""), 0
	}
	addr := string(srv.TailcatAddr())
	id := atomic.AddUintptr(&nextID, 1)
	sess := &TailcatSession{
		id:       id,
		server:   srv,
		listener: ln,
		cancel:   cancel,
		isServer: true,
		addr:     addr,
		dataCb:   dataCb,
		stateCb:  stateCb,
	}
	sessionMap.Store(id, sess)
	sess.invokeState(0, "listening")

	sess.wg.Add(1)
	go func() {
		defer sess.wg.Done()
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		if !sess.setConn(conn) {
			return
		}
		sess.invokeState(1, "connected")
		readLoop(sess, conn)
	}()

	return C.CString(addr), C.uintptr_t(id)
}

//export TailcatStartClient
func TailcatStartClient(serverAddr *C.char, dataCb C.DataCallback, stateCb C.StateCallback) C.uintptr_t {
	addr := C.GoString(serverAddr)
	ctx, cancel := context.WithCancel(context.Background())
	client := tailcat.NewClient(tailcat.Addr(addr))
	id := atomic.AddUintptr(&nextID, 1)
	sess := &TailcatSession{
		id:       id,
		client:   client,
		cancel:   cancel,
		isServer: false,
		addr:     addr,
		dataCb:   dataCb,
		stateCb:  stateCb,
	}
	sessionMap.Store(id, sess)
	sess.invokeState(0, "dialing")

	sess.wg.Add(1)
	go func() {
		defer sess.wg.Done()
		dialCtx, dialCancel := context.WithTimeout(ctx, 20*time.Second)
		defer dialCancel()
		conn, err := client.Dial(dialCtx, "tcp", ":0")
		if err != nil {
			sess.invokeState(2, "dial_failed: "+err.Error())
			return
		}
		if !sess.setConn(conn) {
			return
		}
		sess.invokeState(1, "connected")
		readLoop(sess, conn)
	}()

	return C.uintptr_t(id)
}

//export TailcatSend
func TailcatSend(id C.uintptr_t, isBinary int32, data *C.uint8_t, length int32) int32 {
	v, ok := sessionMap.Load(uintptr(id))
	if !ok {
		return -1
	}
	sess := v.(*TailcatSession)
	if length < 0 {
		return -1
	}
	payload := C.GoBytes(unsafe.Pointer(data), C.int(length))

	sess.sendMu.Lock()
	defer sess.sendMu.Unlock()
	if sess.closed.Load() {
		return -2
	}
	sess.connMu.Lock()
	conn := sess.conn
	sess.connMu.Unlock()
	if conn == nil {
		return -2
	}

	hdr := make([]byte, 5)
	binary.BigEndian.PutUint32(hdr[0:4], uint32(length))
	hdr[4] = byte(isBinary)

	if err := writeFull(conn, hdr); err != nil {
		return -1
	}
	if err := writeFull(conn, payload); err != nil {
		return -1
	}
	return 0
}

//export TailcatIsDirect
func TailcatIsDirect(id C.uintptr_t) int32 {
	v, ok := sessionMap.Load(uintptr(id))
	if !ok {
		return 0
	}
	sess := v.(*TailcatSession)
	if sess.server != nil {
		st := sess.server.Status()
		if st != nil {
			for _, p := range st.Peer {
				if p.CurAddr != "" {
					return 1 // Direct UDP
				}
			}
		}
	}
	return 0 // Relayed or unknown
}

//export TailcatClose
func TailcatClose(id C.uintptr_t) {
	v, ok := sessionMap.LoadAndDelete(uintptr(id))
	if !ok {
		return
	}
	sess := v.(*TailcatSession)
	sess.closed.Store(true)
	if sess.cancel != nil {
		sess.cancel()
	}

	sess.connMu.Lock()
	conn := sess.conn
	sess.conn = nil
	sess.connMu.Unlock()
	if conn != nil {
		_ = conn.Close()
	}

	if sess.listener != nil {
		_ = sess.listener.Close()
	}
	if sess.server != nil {
		_ = sess.server.Close()
	}
	if sess.client != nil {
		_ = sess.client.Close()
	}

	sess.wg.Wait()
	sess.cbMu.Lock()
	sess.cbClosed = true
	sess.cbMu.Unlock()
}

func main() {}
