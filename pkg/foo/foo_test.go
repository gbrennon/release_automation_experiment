package foo

import (
    "testing"
    "bytes"
)

func TestFoo(t *testing.T) {
	expected := "Foo"

	result := Foo()

	if result != expected {
		t.Errorf("Expected %s, got %s", expected, result)
	}
}

func TestPrintFoo(t *testing.T) {
	var buf bytes.Buffer
	PrintFoo(&buf)

	result := buf.String()

	expected := "Foo\n"
	if result != expected {
		t.Errorf("Expected %q, got %q", expected, result)
	}
}
