//go:build tailcat_ctest

package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func testSessionID() uintptr {
	return atomic.AddUintptr(&nextID, 1)
}

func TestSharedLibraryExportsFullABI(t *testing.T) {
	libPath := os.Getenv("TAILCAT_TEST_SHARED_LIB")
	if libPath == "" {
		t.Skip("TAILCAT_TEST_SHARED_LIB not set; build the c-shared fixture first")
	}
	for _, symbol := range []string{
		"TailcatStartServer", "TailcatStartClient", "TailcatSend",
		"TailcatIsDirect", "TailcatClose", "TailcatFree",
	} {
		if !sharedLibraryExports(libPath, symbol) {
			t.Fatalf("%s does not export %s", libPath, symbol)
		}
	}
}

func TestNotifyStateTransfersStringOwnership(t *testing.T) {
	resetCapture()
	sess := &TailcatSession{id: 1}
	installCaptureCallbacks(sess)
	sess.invokeState(7, "listening")

	if got := capturedStateCount(); got != 1 {
		t.Fatalf("state callback count = %d, want 1", got)
	}
	if got := capturedState(); got != "listening" {
		t.Fatalf("state info = %q, want %q", got, "listening")
	}

	churnCAllocations(16)
	if got := capturedState(); got != "listening" {
		t.Fatalf("state info after allocation churn = %q; buffer was released by native code", got)
	}

	freeCapturedState()
}

func TestTransferredBuffersAreReleasedByExportedAllocator(t *testing.T) {
	resetCapture()
	sess := &TailcatSession{id: 3}
	installCaptureCallbacks(sess)

	// State info is a C.CString and data is C.CBytes. Both are handed to the
	// other side; freeCapturedState/Data release them via the exported
	// TailcatFree symbol, the same entry point Dart must use.
	for i := 0; i < 32; i++ {
		sess.invokeState(0, "listening")
		if got := capturedState(); got != "listening" {
			t.Fatalf("state info = %q, want %q", got, "listening")
		}
		freeCapturedState()

		payload := []byte{byte(i), byte(i + 1), 0xFF}
		sess.invokeData(1, payload)
		if got := string(capturedData()); got != string(payload) {
			t.Fatalf("data buffer = %v, want %v", got, payload)
		}
		freeCapturedData()
	}

	if got, want := capturedStateCount(), int32(32); got != want {
		t.Fatalf("state callback count = %d, want %d", got, want)
	}
	if got, want := capturedDataCount(), int32(32); got != want {
		t.Fatalf("data callback count = %d, want %d", got, want)
	}
}

func TestInvokeDataCopiesGoBuffer(t *testing.T) {
	resetCapture()
	sess := &TailcatSession{id: 2}
	installCaptureCallbacks(sess)
	payload := []byte("binary-frame")
	sess.invokeData(1, payload)

	if got := capturedDataCount(); got != 1 {
		t.Fatalf("data callback count = %d, want 1", got)
	}
	for i := range payload {
		payload[i] = 'X'
	}
	if got := string(capturedData()); got != "binary-frame" {
		t.Fatalf("data callback buffer = %q, want %q", got, "binary-frame")
	}

	freeCapturedData()
}

func TestReadLoopAndCloseStopCallbacks(t *testing.T) {
	resetCapture()
	id := testSessionID()
	sess := &TailcatSession{id: id}
	installCaptureCallbacks(sess)
	sessionMap.Store(id, sess)
	defer sessionMap.Delete(id)

	server, client := net.Pipe()
	defer client.Close()
	if !sess.setConn(server) {
		t.Fatal("setConn rejected an open session")
	}

	sess.wg.Add(1)
	go func() {
		defer sess.wg.Done()
		readLoop(sess, server)
	}()

	frame := makeFrame(1, []byte("hello"))
	if err := writeFull(client, frame); err != nil {
		t.Fatalf("write frame: %v", err)
	}
	waitFor(t, func() bool {
		return capturedDataCount() == 1
	}, "readLoop delivery")

	if got := string(capturedData()); got != "hello" {
		t.Fatalf("readLoop data = %q, want %q", got, "hello")
	}
	freeCapturedData()
	freeCapturedState()

	testClose(id)

	sess.invokeState(2, "late")
	sess.invokeData(1, []byte("late"))
	time.Sleep(20 * time.Millisecond)

	if got := capturedDataCount(); got != 1 {
		t.Fatalf("data callbacks after close = %d, want 1", got)
	}
	if got := capturedStateCount(); got != 0 {
		t.Fatalf("state callbacks after close = %d, want 0", got)
	}
	if _, ok := sessionMap.Load(id); ok {
		t.Fatal("session remained registered after close")
	}
}

func TestConcurrentSendsKeepWholeFrames(t *testing.T) {
	conn := &recordingConn{}
	id := testSessionID()
	sess := &TailcatSession{id: id, conn: conn}
	sessionMap.Store(id, sess)
	defer sessionMap.Delete(id)

	const count = 64
	payloads := make([][]byte, count)
	for i := range payloads {
		payloads[i] = []byte(fmt.Sprintf("frame-%03d-%s", i, strings.Repeat("x", i%17)))
	}

	var wg sync.WaitGroup
	results := make(chan int32, count)
	for i := 0; i < count; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			payload := payloads[i]
			results <- testSend(id, 1, payload)
		}(i)
	}
	wg.Wait()
	close(results)

	for result := range results {
		if result != 0 {
			t.Fatalf("TailcatSend returned %d, want 0", result)
		}
	}

	frames, err := parseFrames(conn.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if len(frames) != count {
		t.Fatalf("received %d frames, want %d", len(frames), count)
	}
	seen := make(map[string]bool, count)
	for _, frame := range frames {
		if frame.binary != 1 {
			t.Fatalf("frame binary flag = %d, want 1", frame.binary)
		}
		seen[string(frame.payload)] = true
	}
	for _, payload := range payloads {
		if !seen[string(payload)] {
			t.Fatalf("missing or corrupted frame %q", payload)
		}
	}
}

func TestSendHandlesShortWrites(t *testing.T) {
	conn := &recordingConn{maxChunk: 3}
	id := testSessionID()
	sess := &TailcatSession{id: id, conn: conn}
	sessionMap.Store(id, sess)
	defer sessionMap.Delete(id)

	payload := []byte("abcdefghijklmnop")
	if got := testSend(id, 0, payload); got != 0 {
		t.Fatalf("TailcatSend returned %d, want 0", got)
	}
	want := makeFrame(0, payload)
	if got := conn.Bytes(); !bytes.Equal(got, want) {
		t.Fatalf("frame bytes = %v, want %v", got, want)
	}
}

func TestSendTreatsZeroLengthWriteAsFailure(t *testing.T) {
	conn := &recordingConn{zeroWrite: true}
	id := testSessionID()
	sess := &TailcatSession{id: id, conn: conn}
	sessionMap.Store(id, sess)
	defer sessionMap.Delete(id)

	if got := testSend(id, 1, []byte("abc")); got != -1 {
		t.Fatalf("TailcatSend returned %d, want -1", got)
	}
}

func TestSendReportsMissingNilAndFailedConnections(t *testing.T) {
	if got := testSend(99999999, 1, []byte("abc")); got != -1 {
		t.Fatalf("missing session result = %d, want -1", got)
	}

	id := testSessionID()
	sess := &TailcatSession{id: id}
	sessionMap.Store(id, sess)
	defer sessionMap.Delete(id)

	if got := testSend(id, 1, []byte("abc")); got != -2 {
		t.Fatalf("nil connection result = %d, want -2", got)
	}

	if !sess.setConn(&recordingConn{writeErr: errors.New("write failed")}) {
		t.Fatal("setConn rejected an open session")
	}
	if got := testSend(id, 1, []byte("abc")); got != -1 {
		t.Fatalf("write error result = %d, want -1", got)
	}

	sess.closed.Store(true)
	if got := testSend(id, 1, []byte("abc")); got != -2 {
		t.Fatalf("closed session result = %d, want -2", got)
	}
}

func makeFrame(isBinary byte, payload []byte) []byte {
	frame := make([]byte, 5+len(payload))
	binary.BigEndian.PutUint32(frame[0:4], uint32(len(payload)))
	frame[4] = isBinary
	copy(frame[5:], payload)
	return frame
}

type parsedFrame struct {
	binary  byte
	payload []byte
}

func parseFrames(data []byte) ([]parsedFrame, error) {
	var frames []parsedFrame
	for len(data) > 0 {
		if len(data) < 5 {
			return nil, fmt.Errorf("truncated header: %d bytes left", len(data))
		}
		n := int(binary.BigEndian.Uint32(data[0:4]))
		if n < 0 || len(data) < 5+n {
			return nil, fmt.Errorf("truncated payload: header=%d available=%d", n, len(data)-5)
		}
		frames = append(frames, parsedFrame{
			binary:  data[4],
			payload: append([]byte(nil), data[5:5+n]...),
		})
		data = data[5+n:]
	}
	return frames, nil
}

func waitFor(t *testing.T, condition func() bool, label string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		runtime.Gosched()
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", label)
}

type recordingConn struct {
	mu        sync.Mutex
	buf       bytes.Buffer
	maxChunk  int
	zeroWrite bool
	writeErr  error
}

func (c *recordingConn) Write(p []byte) (int, error) {
	if c.writeErr != nil {
		return 0, c.writeErr
	}
	if c.zeroWrite {
		return 0, nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	n := len(p)
	if c.maxChunk > 0 && n > c.maxChunk {
		n = c.maxChunk
	}
	c.buf.Write(p[:n])
	runtime.Gosched()
	return n, nil
}

func (c *recordingConn) Bytes() []byte {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]byte(nil), c.buf.Bytes()...)
}

func (c *recordingConn) Read([]byte) (int, error)         { return 0, io.EOF }
func (c *recordingConn) Close() error                     { return nil }
func (c *recordingConn) LocalAddr() net.Addr              { return nil }
func (c *recordingConn) RemoteAddr() net.Addr             { return nil }
func (c *recordingConn) SetDeadline(time.Time) error      { return nil }
func (c *recordingConn) SetReadDeadline(time.Time) error  { return nil }
func (c *recordingConn) SetWriteDeadline(time.Time) error { return nil }

func TestCloseUnblocksInFlightSend(t *testing.T) {
	conn := newBlockingConn()
	id := testSessionID()
	sess := &TailcatSession{id: id}
	if !sess.setConn(conn) {
		t.Fatal("setConn rejected an open session")
	}
	sessionMap.Store(id, sess)
	defer sessionMap.Delete(id)

	done := make(chan int32, 1)
	go func() {
		done <- testSend(id, 1, []byte("payload"))
	}()

	select {
	case <-conn.started:
	case <-time.After(2 * time.Second):
		t.Fatal("send did not start writing")
	}

	closed := make(chan struct{})
	go func() {
		testClose(id)
		close(closed)
	}()

	select {
	case <-closed:
	case <-time.After(2 * time.Second):
		t.Fatal("TailcatClose did not unblock the in-flight send")
	}

	select {
	case result := <-done:
		if result != -1 {
			t.Fatalf("blocked send result = %d, want -1", result)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("send did not finish after close")
	}
}

type blockingConn struct {
	recordingConn
	started   chan struct{}
	closeCh   chan struct{}
	startOnce sync.Once
	closeOnce sync.Once
}

func newBlockingConn() *blockingConn {
	return &blockingConn{
		started: make(chan struct{}),
		closeCh: make(chan struct{}),
	}
}

func (c *blockingConn) Write(p []byte) (int, error) {
	c.startOnce.Do(func() { close(c.started) })
	<-c.closeCh
	return 0, io.ErrClosedPipe
}

func (c *blockingConn) Close() error {
	c.closeOnce.Do(func() { close(c.closeCh) })
	return nil
}
