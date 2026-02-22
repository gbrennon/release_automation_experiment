package foo

import "testing"

func TestFoo(t *testing.T) {
	expected := "Foo"

	result := Foo()

	if result != expected {
		t.Errorf("Expected %s, got %s", expected, result)
	}
}
