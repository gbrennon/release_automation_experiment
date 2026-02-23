package foo

import (
	"fmt"
	"io"
)

func Foo() string {
	return "Foo"
}

func PrintFoo(w io.Writer) {
	fmt.Fprintln(w, Foo())
}
