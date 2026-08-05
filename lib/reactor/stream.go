//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the Apache License, Version 2.0. Full text in
//	../convertbase/LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

//go:build wasip1

// Push-style streaming, the half of the ABI the one-shot surface left open.
// A stream is the reactor's form of the command's piped binary mode: raw bytes
// on one side, a raw-capable base on the other, or two text bases routed
// through bytes. The host pushes input with stream_write and drains output
// chunks as they come; stream_finish flushes the tail.
//
// The conversion itself is the library's own streaming code, fed through an
// io.Pipe by a goroutine per stream. An exported call that blocks on the pipe
// just lets the Go scheduler run the converter; goroutines only ever run
// inside a host call, so between calls a stream is frozen, and output can
// trail input by up to one internal chunk until finish. Pairs the library
// cannot stream (the codecs, mainly) buffer inside the goroutine and emit
// everything at finish - same behavior as the command, and documented.
//
// Output chunks are module-owned and reused per stream: the host copies a
// chunk out before its next call on that stream, the same contract as
// last_error_text. Streams never touch the regions map.
package main

import (
	"errors"
	"io"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

var (
	streams      = map[uint32]*stream{}
	nextStreamID uint32

	// The raw-byte base, resolved once; every stream routes through or ends at it.
	bytesBase *convertbase.Base
)

type stream struct {
	pw       *io.PipeWriter
	done     chan error
	out      *streamOut
	finished bool
	failed   bool
}

// streamOut collects converter output between host calls. No locking: wasip1
// is single-threaded and the converter only runs inside an export call.
type streamOut struct{ buf []byte }

func (o *streamOut) Write(p []byte) (int, error) {
	o.buf = append(o.buf, p...)
	return len(p), nil
}

// take hands the collected output to the host and resets the buffer for
// reuse. Zero means an empty chunk; the host tells that from failure by
// last_error_code, per the README.
func (o *streamOut) take() uint64 {
	if len(o.buf) == 0 {
		return 0
	}
	packed := pack(o.buf)
	o.buf = o.buf[:0]
	return packed
}

// runStream is the converter goroutine. It tries the library's streaming
// paths first and falls back to buffering the whole input for the pairs that
// cannot stream, so every raw-capable pair works through one API. On exit it
// closes the read side, so a writer blocked mid-stream fails fast instead of
// hanging forever.
func runStream(s *stream, pr *io.PipeReader, from, to *convertbase.Base) {
	handled, err := convertbase.StreamConvert(pr, s.out, from, to)
	if !handled && err == nil && !from.Binary && !to.Binary {
		handled, err = convertbase.StreamBytesRoute(pr, s.out, from, to, bytesBase)
	}
	if !handled && err == nil {
		err = bufferedStream(pr, s.out, from, to)
	}
	if err != nil {
		pr.CloseWithError(err)
	} else {
		pr.Close()
	}
	s.done <- err
}

// bufferedStream is the fallback for pairs the streaming paths decline: read
// everything, convert once, emit once. This is what the command does for the
// same pairs, so a codec stream is correct, just not constant-memory.
func bufferedStream(pr io.Reader, w io.Writer, from, to *convertbase.Base) error {
	data, err := io.ReadAll(pr)
	if err != nil {
		return err
	}
	var out string
	if from.Binary || to.Binary {
		out, err = convertbase.Convert(string(data), from, to, -1)
	} else {
		var mid string
		mid, err = convertbase.Convert(string(data), from, bytesBase, -1)
		if err == nil {
			out, err = convertbase.Convert(mid, bytesBase, to, -1)
		}
	}
	if err != nil {
		return err
	}
	_, err = w.Write([]byte(out))
	return err
}

// openStream resolves a handle, with the same BadArg reporting everywhere.
func openStream(h uint32) (*stream, bool) {
	s, ok := streams[h]
	if !ok {
		setErr(errBadArg, "not an open stream handle")
		return nil, false
	}
	return s, true
}

// stream_new opens a raw binary conversion stream and returns its handle
// (positive), or the negated error code. Both sides must carry raw bytes:
// bytes itself, a power-of-2 base, or a defined binary-to-text codec.
//
//go:wasmexport stream_new
func streamNew(fromPtr, fromLen, toPtr, toLen uint32) int64 {
	clearErr()
	if !ready() {
		return -errInternal
	}
	if bytesBase == nil {
		b, err := reg.Lookup("bytes")
		if err != nil {
			setErr(errInternal, "bytes base missing from registry")
			return -errInternal
		}
		bytesBase = b
	}
	from, ok := namedBase(fromPtr, fromLen)
	if !ok {
		return -int64(lastCode)
	}
	to, ok := namedBase(toPtr, toLen)
	if !ok {
		return -int64(lastCode)
	}
	// Refuse a pair raw conversion itself would refuse, here rather than at
	// finish. Convert with the offending side against bytes produces the
	// library's own message for it, so the text never drifts from the
	// command's.
	for _, b := range []*convertbase.Base{from, to} {
		if !b.RawCodec() && !b.Binary {
			_, err := convertbase.Convert("", b, bytesBase, -1)
			if err == nil {
				err = errors.New("base cannot carry raw bytes")
			}
			setErr(errBadInput, err.Error())
			return -errBadInput
		}
	}
	nextStreamID++
	for streams[nextStreamID] != nil || nextStreamID == 0 {
		nextStreamID++
	}
	pr, pw := io.Pipe()
	s := &stream{pw: pw, done: make(chan error, 1), out: &streamOut{}}
	streams[nextStreamID] = s
	go runStream(s, pr, from, to)
	return int64(nextStreamID)
}

// stream_write pushes input bytes and returns the packed output produced so
// far. The chunk is module-owned and reused: copy it out before the next call
// on this stream. Zero with last_error_code 0 is an empty chunk (output can
// trail input); zero with a code set is a failure, and the stream is dead
// except to stream_free. A zero length is a legal drain-only call.
//
//go:wasmexport stream_write
func streamWrite(handle, ptr, n uint32) uint64 {
	clearErr()
	s, ok := openStream(handle)
	if !ok {
		return 0
	}
	if s.finished || s.failed {
		setErr(errBadArg, "stream already finished or failed")
		return 0
	}
	data, ok := hostBytes(ptr, n)
	if !ok {
		return 0
	}
	if len(data) > 0 {
		if _, err := s.pw.Write(data); err != nil {
			s.failed = true
			setErr(classify(err), err.Error())
			return 0
		}
	}
	return s.out.take()
}

// stream_finish ends the input, waits for the converter to drain, and returns
// the packed tail output (zero with last_error_code 0 when the tail is
// empty). The stream stays open until stream_free, so the host can read the
// chunk first.
//
//go:wasmexport stream_finish
func streamFinish(handle uint32) uint64 {
	clearErr()
	s, ok := openStream(handle)
	if !ok {
		return 0
	}
	if s.finished {
		setErr(errBadArg, "stream already finished")
		return 0
	}
	s.finished = true
	_ = s.pw.Close()
	if err := <-s.done; err != nil {
		s.failed = true
		setErr(classify(err), err.Error())
		return 0
	}
	return s.out.take()
}

// stream_free closes a stream in any state, finished or not, and releases it.
//
//go:wasmexport stream_free
func streamFree(handle uint32) int32 {
	clearErr()
	s, ok := openStream(handle)
	if !ok {
		return errBadArg
	}
	if !s.finished {
		s.pw.CloseWithError(errors.New("stream freed before finish"))
		<-s.done
	}
	delete(streams, handle)
	return errNone
}

// stream_count reports open streams, the leak check stream_new's side of the
// ABI gets, matching region_count for regions.
//
//go:wasmexport stream_count
func streamCount() uint32 { return uint32(len(streams)) }
